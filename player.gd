extends CharacterBody2D

@export var speed: float = 75.0
var is_in_chest := false
var move_dir := Vector2.ZERO
var last_move_dir: Vector2 = Vector2.DOWN 
var is_hidden: bool = false 
var is_dead: bool = false  # Nouvelle variable pour l'état de mort

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel
@onready var camera: Camera2D = $Camera2D
@onready var chest_area: Area2D = $ChestDetector
@onready var collision_shape: CollisionShape2D = $CollisionShape2D 
@onready var press_space_label: Label = $PressSpaceLabel 
@onready var is_occupied_label: Label = $IsOccupiedLabel 

func _ready() -> void:
	# FIX: Désactive le _process si le réseau n'est pas actif
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		set_process_mode(PROCESS_MODE_DISABLED)
		return
		
	camera.enabled = is_multiplayer_authority()
	
	_connect_chest_signals()
	
	# Mise à jour initiale (Couleur + Nom)
	_update_visuals()
	
	# Connexion unique pour mettre à jour les visuels quand le lobby change
	NetworkHandler.lobby_players_updated.connect(func(_p): _update_visuals())
	
	# Gestion des labels (autorité uniquement)
	if is_multiplayer_authority():
		if press_space_label: press_space_label.visible = false
		if is_occupied_label: is_occupied_label.visible = false
	else:
		if press_space_label: press_space_label.queue_free()
		if is_occupied_label: is_occupied_label.queue_free()
	
	print("--- PLAYER READY (ID: %s) ---" % get_multiplayer_authority())

# Cette fonction gère TOUT (Nom, Rôle et Couleur)
func _update_visuals() -> void:
	if not name_label: return
	
	# Récupère l'ID via l'autorité multi-joueur
	var id = get_multiplayer_authority()
	var player_data = NetworkHandler.players.get(id)
	
	if player_data:
		# 1. Nom
		var name_text = ""
		if player_data.has("name"):
			name_text = player_data["name"]
		else:
			name_text = "Player %s" % id
		
		# 2. Rôle (ajouter entre parenthèses si présent)
		if player_data.has("role"):
			name_text += " (%s)" % player_data["role"]
		
		name_label.text = name_text
		
		# 3. Couleur
		if player_data.has("color"):
			anim.modulate = player_data["color"]
			name_label.modulate = player_data["color"] # Colore aussi le nom
		else:
			anim.modulate = Color.WHITE
			name_label.modulate = Color.WHITE
	else:
		name_label.text = "Player %s" % id
		anim.modulate = Color.WHITE
		name_label.modulate = Color.WHITE

func _connect_chest_signals() -> void:
	chest_area.area_entered.connect(_on_area_entered, 4)
	chest_area.area_exited.connect(_on_area_exited, 4)

func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	
	# Vérifier si le joueur est mort - empêcher tout mouvement et interaction
	if is_dead or NetworkHandler.is_player_dead(get_multiplayer_authority()):
		is_dead = true
		velocity = Vector2.ZERO
		move_and_slide()
		# Ne pas envoyer de mise à jour réseau si mort
		return

	# LOGIQUE D'AFFICHAGE/NETTOYAGE UI
	if not is_hidden:
		var overlapping_chest = chest_area.get_overlapping_areas().any(func(area): return area.has_meta("chest"))
		
		if not overlapping_chest:
			if is_in_chest: # On vient de sortir
				is_in_chest = false
				if press_space_label: press_space_label.visible = false
				if is_occupied_label: is_occupied_label.visible = false
		else:
			is_in_chest = true

	if Input.is_action_just_pressed("ui_accept"):
		_try_hide_or_open_chest()
	
	# Exemple: Tuer un joueur proche avec la touche K (vous pouvez changer la touche)
	if Input.is_action_just_pressed("kill"):  # ou une autre action
		_try_kill_nearby_player()

	if is_hidden:
		velocity = Vector2.ZERO
		move_and_slide() 
		return 
	
	# Mouvement
	var iv = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)

	move_dir = iv.normalized()
	if move_dir != Vector2.ZERO: last_move_dir = move_dir

	velocity = move_dir * speed
	move_and_slide()

	rpc("_net_state", global_position, move_dir, last_move_dir)
	_update_animation()

func _try_hide_or_open_chest():
	if not is_multiplayer_authority(): return

	var overlapping_areas = chest_area.get_overlapping_areas()
	var chest_area_found = null
	
	for area in overlapping_areas:
		if area.has_meta("chest"):
			chest_area_found = area
			break
			
	if not chest_area_found: return 

	if is_hidden:
		NetworkHandler.rpc_id(1, "request_player_hide_state", false, chest_area_found.global_position) 
	else:
		NetworkHandler.rpc_id(1, "request_player_hide_state", true, chest_area_found.global_position) 

# --- RPCs ---

@rpc("any_peer", "call_local", "unreliable")
func sync_player_visual_state(new_state: bool):
	is_hidden = new_state
	anim.visible = not new_state
	name_label.visible = not new_state
	collision_shape.disabled = new_state
	
	if is_multiplayer_authority():
		if new_state: # Caché
			if press_space_label: press_space_label.visible = false
			if is_occupied_label: is_occupied_label.visible = false
		else: # Révélé
			is_in_chest = false # Force le recheck
			var overlapping = chest_area.get_overlapping_areas()
			for area in overlapping:
				if area.has_meta("chest"):
					is_in_chest = true
					NetworkHandler.rpc_id(1, "request_chest_occupancy_state", area.global_position)
					break
			
	if new_state: anim.stop()
	else: _update_animation()

@rpc("reliable")
func update_chest_ui(is_occupied: bool):
	if not is_multiplayer_authority(): return
	
	if is_in_chest and not is_hidden:
		if is_occupied:
			if is_occupied_label: is_occupied_label.visible = true
			if press_space_label: press_space_label.visible = false
		else:
			if is_occupied_label: is_occupied_label.visible = false
			if press_space_label: press_space_label.visible = true
	elif is_hidden:
		if is_occupied_label: is_occupied_label.visible = false
		if press_space_label: press_space_label.visible = false

@rpc("any_peer", "call_local", "unreliable")
func _net_state(pos: Vector2, dir: Vector2, last_dir: Vector2) -> void:
	if is_multiplayer_authority(): return
	
	# Ne pas mettre à jour la position si le joueur est mort
	if is_dead:
		return
		
	global_position = pos
	move_dir = dir
	last_move_dir = last_dir
	if not is_hidden: _update_animation()

func _update_animation() -> void:
	# Si le joueur est mort, jouer l'animation death en boucle
	if is_dead:
		# Vérifier si l'animation death existe avant de la jouer
		if anim.sprite_frames.has_animation("death"):
			anim.play("death")
		else:
			# Si l'animation n'existe pas, arrêter l'animation
			anim.stop()
		return
	
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

func _on_area_entered(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		is_in_chest = true 
		if not is_hidden and press_space_label: press_space_label.visible = true
		NetworkHandler.rpc_id(1, "request_chest_occupancy_state", a.global_position)

func _on_area_exited(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		is_in_chest = false

# Nouvelle fonction pour tuer un joueur proche
func _try_kill_nearby_player() -> void:
	if not is_multiplayer_authority():
		return
	
	# Vérifier que le joueur n'est pas mort
	if NetworkHandler.is_player_dead(get_multiplayer_authority()):
		return
	
	# Optionnel: Vérifier que seul un loup-garou peut tuer
	if not NetworkHandler.is_werewolf(get_multiplayer_authority()):
		print("Seuls les loups-garous peuvent tuer")
		return
	
	var my_id = get_multiplayer_authority()
	var kill_range = 15.0  # Distance maximale pour tuer
	
	# Chercher les joueurs proches
	var players_root = get_tree().get_root().get_node_or_null("TestScene/Players")
	if not players_root:
		return
	
	for child in players_root.get_children():
		if child == self:
			continue
		
		var target_id = child.get_multiplayer_authority()
		
		# Vérifier que le joueur cible n'est pas mort
		if NetworkHandler.is_player_dead(target_id):
			continue
		
		# Vérifier la distance
		var distance = global_position.distance_to(child.global_position)
		if distance <= kill_range:
			# Envoyer la demande de kill au serveur
			NetworkHandler.rpc_id(1, "request_kill_player", target_id)
			print("Tentative de tuer le joueur %d" % target_id)
			break

# Nouvelle fonction RPC pour jouer l'animation death
@rpc("any_peer", "call_local", "reliable")
func play_death_animation() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	
	# Désactiver les interactions
	collision_shape.disabled = true
	
	# Masquer les labels UI si présents
	if press_space_label:
		press_space_label.visible = false
	if is_occupied_label:
		is_occupied_label.visible = false
	
	# Jouer l'animation death
	if anim.sprite_frames.has_animation("death"):
		anim.play("death")
		# S'assurer que l'animation reste en boucle (si configurée ainsi)
		print("Animation death jouée pour le joueur %d" % get_multiplayer_authority())
	else:
		push_warning("Animation 'death' non trouvée dans les SpriteFrames")
		anim.stop()
	
	# Empêcher toute mise à jour de position
	move_dir = Vector2.ZERO
