extends CharacterBody2D

@export var speed: float = 150.0
var is_in_chest := false
var move_dir := Vector2.ZERO

var last_move_dir: Vector2 = Vector2.DOWN 
var is_hidden: bool = false 

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel
@onready var camera: Camera2D = $Camera2D
@onready var chest_area: Area2D = $ChestDetector
@onready var chest_manager: Node = $"../../TileMap_Interactions" 
@onready var collision_shape: CollisionShape2D = $CollisionShape2D 
@onready var press_space_label: Label = $PressSpaceLabel 
@onready var is_occupied_label: Label = $IsOccupiedLabel 

func _enter_tree() -> void:
	pass

func _ready() -> void:
	# FIX: Désactive le _process si le réseau n'est pas actif pour éviter les erreurs au démarrage.
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		set_process_mode(PROCESS_MODE_DISABLED)
		return
		
	camera.enabled = is_multiplayer_authority()
	
	_connect_chest_signals()
	_update_name()
	NetworkHandler.lobby_players_updated.connect(_update_name)
	
	# Initialisation des labels (seulement pour le joueur autorisé)
	if is_multiplayer_authority():
		if press_space_label:
			press_space_label.visible = false
		if is_occupied_label:
			is_occupied_label.visible = false
	else:
		# Libérer les labels sur les clients non-autoritaires
		if press_space_label:
			press_space_label.queue_free()
		if is_occupied_label:
			is_occupied_label.queue_free()
	
	print("--- PLAYER READY (ID: %s) ---" % get_multiplayer_authority())

func _connect_chest_signals() -> void:
	chest_area.area_entered.connect(_on_area_entered, 4)
	chest_area.area_exited.connect(_on_area_exited, 4)

func _update_name(players = null) -> void: 
	if name_label:
		var id := get_multiplayer_authority()
		var player_data = NetworkHandler.players.get(id)
		if player_data and player_data.has("name"):
			name_label.text = player_data["name"]
		else:
			name_label.text = "Player %s" % id


func _process(delta: float) -> void:
	# VERIFICATION DE SECURITE
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		return
		
	if not is_multiplayer_authority(): return

	# LOGIQUE D'AFFICHAGE/NETTOYAGE UI ROBUSTE (Gère la persistance et le masquage à la sortie)
	if not is_hidden:
		var overlapping_chest = chest_area.get_overlapping_areas().any(func(area): return area.has_meta("chest"))
		
		if not overlapping_chest:
			# Nettoyage et masquage UNIQUEMENT si nous ne sommes PAS dans la zone (fixe le bug de persistance)
			if is_in_chest:
				print("DEBUG [_process]: Sortie de zone physique détectée. Nettoyage UI.")
			
			is_in_chest = false
			if press_space_label:
				press_space_label.visible = false
			if is_occupied_label:
				is_occupied_label.visible = false
		else:
			# Si nous sommes dans la zone, is_in_chest est VRAI. 
			is_in_chest = true


	if Input.is_action_just_pressed("ui_accept"):
		_try_hide_or_open_chest()

	if is_hidden:
		velocity = Vector2.ZERO
		move_and_slide() 
		return 
	
	var iv = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)

	move_dir = iv.normalized()
	
	if move_dir != Vector2.ZERO:
		last_move_dir = move_dir

	if is_in_chest and move_dir == Vector2.ZERO:
		velocity = Vector2.ZERO
	else:
		velocity = move_dir * speed
		
	move_and_slide()

	rpc("_net_state", global_position, move_dir, last_move_dir)
	_update_animation()

#  Bloquer l'interaction si aucun coffre n'est chevauché.
func _try_hide_or_open_chest():
	if not is_multiplayer_authority(): return

	var overlapping_areas = chest_area.get_overlapping_areas()
	var chest_area_found = null
	
	# Rechercher un coffre chevauché
	for area in overlapping_areas:
		if area.has_meta("chest"):
			chest_area_found = area
			break
			
	# Si aucun coffre n'est trouvé, annuler l'interaction.
	if not chest_area_found:
		print("DEBUG [_try_hide_or_open_chest]: Tentative d'interaction hors zone. Annulée.")
		return 

	if is_hidden:
		print("DEBUG [_try_hide_or_open_chest]: Demande de RÉVÉLATION.")
		var chest_pos = chest_area_found.global_position
		NetworkHandler.rpc_id(1, "request_player_hide_state", false, chest_pos) 
		return

	if chest_area_found:
		print("DEBUG [_try_hide_or_open_chest]: Demande de MASQUAGE (interaction).")
		var chest_pos = chest_area_found.global_position 
		NetworkHandler.rpc_id(1, "request_player_hide_state", true, chest_pos) 
		return

# --- RPC ET SYNCHRONISATION VISUELLE ---

@rpc("any_peer", "call_local", "unreliable")
func sync_player_visual_state(new_state: bool):
	is_hidden = new_state
	print("DEBUG [sync_player_visual_state]: Nouvel état caché: %s. is_in_chest: %s" % [new_state, is_in_chest])
	
	anim.visible = not new_state
	name_label.visible = not new_state
	collision_shape.disabled = new_state
	
	# MISE À JOUR DU LABEL 
	if is_multiplayer_authority():
		if new_state: # Hiding (Masquer)
			if press_space_label: press_space_label.visible = false
			if is_occupied_label: is_occupied_label.visible = false
		else: # Unhiding (Révéler)
			# Re-vérification de l'état du coffre après s'être révélé
			var overlapping_areas = chest_area.get_overlapping_areas()
			is_in_chest = false
			for area in overlapping_areas:
				if area.has_meta("chest"):
					is_in_chest = true
					# On refait une demande d'état rapide pour mettre à jour l'UI après le démasquage
					NetworkHandler.rpc_id(1, "request_chest_occupancy_state", area.global_position)
					print("DEBUG [sync_player_visual_state]: Demande MAJ UI après révélation.")
					break
			
	if new_state:
		anim.stop()
	else:
		_update_animation()

# --- GESTION UI OCCUPATION ---

@rpc("reliable")
func update_chest_ui(is_occupied: bool):
	print("DEBUG [update_chest_ui]: Reçu is_occupied: %s. is_in_chest: %s. is_hidden: %s" % [is_occupied, is_in_chest, is_hidden])
	if not is_multiplayer_authority(): return
	
	# Si le joueur est bien dans la zone et n'est pas caché
	if is_in_chest and not is_hidden:
		if is_occupied:
			# Afficher Occupé
			print("DEBUG [update_chest_ui]: Affichage IsOccupiedLabel.")
			if is_occupied_label: is_occupied_label.visible = true
			if press_space_label: press_space_label.visible = false
		else:
			# Afficher Press Space
			print("DEBUG [update_chest_ui]: Affichage PressSpaceLabel.")
			if is_occupied_label: is_occupied_label.visible = false
			if press_space_label: press_space_label.visible = true
	else:
		# Masquer uniquement si le joueur est caché.
		if is_hidden:
			print("DEBUG [update_chest_ui]: Masquage car is_hidden=true.")
			if is_occupied_label: is_occupied_label.visible = false
			if press_space_label: press_space_label.visible = false

# --- RPC ET ANIMATION STANDARD ---
@rpc("any_peer", "call_local", "unreliable")
func _net_state(pos: Vector2, dir: Vector2, last_dir: Vector2) -> void:
	if is_multiplayer_authority(): return
	global_position = pos
	move_dir = dir
	last_move_dir = last_dir
	
	if not is_hidden: 
		_update_animation()

func _update_animation() -> void:
	var current_dir = move_dir
	
	if current_dir == Vector2.ZERO:
		current_dir = last_move_dir
		
		if current_dir.y > 0: anim.play("idle-down")
		elif current_dir.y < 0: anim.play("idle-up")
		else: anim.play("idle-left-right")
		
		anim.flip_h = current_dir.x < 0
		return
	
	if current_dir.y > 0: anim.play("run-down")
	elif current_dir.y < 0: anim.play("run-up")
	else: anim.play("run-left-right")
	anim.flip_h = current_dir.x < 0

# --- SEGNALS AREA ---

func _on_area_entered(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		print("DEBUG [_on_area_entered]: 📥 ENTRÉE dans zone coffre. is_hidden: %s" % is_hidden)
		is_in_chest = true 
		
		# Afficher PressSpaceLabel immédiatement pour la réactivité. 
		if not is_hidden and press_space_label:
			press_space_label.visible = true
			print("DEBUG [_on_area_entered]: PressSpaceLabel affiché (déclenchement rapide).")
		
		# Demande l'état d'occupation au serveur immédiatement
		var chest_pos = a.global_position
		NetworkHandler.rpc_id(1, "request_chest_occupancy_state", chest_pos)

func _on_area_exited(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		print("DEBUG [_on_area_exited]: 📤 SORTIE de zone coffre. is_in_chest mis à false.")
		# On met le flag à false, le nettoyage de l'UI est géré de manière robuste par _process
		is_in_chest = false
