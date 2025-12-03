extends CharacterBody2D

@export var speed: float = 75.0
var is_in_chest := false
var move_dir := Vector2.ZERO
var last_move_dir: Vector2 = Vector2.DOWN 
var is_hidden: bool = false 

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
	
	_apply_color_from_network()
	
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

func _apply_color_from_network():
	var id = str(name).to_int()
	
	if NetworkHandler.players.has(id):
		var data = NetworkHandler.players[id]
		if data.has("color"):
			$AnimatedSprite2D.modulate = data["color"]
			$NameLabel.text = data["name"]

func _connect_chest_signals() -> void:
	chest_area.area_entered.connect(_on_area_entered, 4)
	chest_area.area_exited.connect(_on_area_exited, 4)

# Cette fonction gère TOUT (Nom et Couleur)
func _update_visuals() -> void:
	if not name_label: return
	
	# Récupère l'ID via le nom du noeud (ex: "1", "34562")
	var id_str = str(name)
	if not id_str.is_valid_int():
		return # Évite les erreurs si le noeud ne s'appelle pas par un chiffre
		
	var id = id_str.to_int()
	var player_data = NetworkHandler.players.get(id)
	
	if player_data:
		# 1. Nom
		if player_data.has("name"):
			name_label.text = player_data["name"]
		
		# 2. Couleur
		if player_data.has("color"):
			anim.modulate = player_data["color"]
			name_label.modulate = player_data["color"] # (Optionnel) colore aussi le nom
	else:
		name_label.text = "Player %s" % id
		anim.modulate = Color.WHITE

func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return

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
	global_position = pos
	move_dir = dir
	last_move_dir = last_dir
	if not is_hidden: _update_animation()

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

func _on_area_entered(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		is_in_chest = true 
		if not is_hidden and press_space_label: press_space_label.visible = true
		NetworkHandler.rpc_id(1, "request_chest_occupancy_state", a.global_position)

func _on_area_exited(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		is_in_chest = false
