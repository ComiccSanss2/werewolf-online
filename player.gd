extends CharacterBody2D

@export var speed: float = 75.0
var is_in_chest := false
var move_dir := Vector2.ZERO
var last_move_dir: Vector2 = Vector2.DOWN 
var is_hidden: bool = false 
var is_dead: bool = false 

@onready var footstep_player: AudioStreamPlayer2D = $FootstepPlayer
@onready var chest_audio_player: AudioStreamPlayer2D = $ChestAudioPlayer
@onready var step_timer: Timer = $StepTimer

var sfx_grass = preload("res://sfx_grass.tres")
var sfx_wood = preload("res://sfx_wood.tres")   
var level_tilemap: TileMap = null
var last_valid_tile_id: int = 0 

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel
@onready var camera: Camera2D = $Camera2D
@onready var chest_area: Area2D = $ChestDetector
@onready var collision_shape: CollisionShape2D = $CollisionShape2D 
@onready var press_space_label: Label = $PressSpaceLabel 
@onready var is_occupied_label: Label = $IsOccupiedLabel 

func _ready() -> void:
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		set_process_mode(PROCESS_MODE_DISABLED)
		return
		
	camera.enabled = is_multiplayer_authority()
	# Chemin mis à jour avec le nom forcé TestScene
	level_tilemap = get_tree().get_root().get_node_or_null("TestScene/TileMap_Interactions/TileMap")
	
	_connect_chest_signals()
	_update_visuals()
	NetworkHandler.lobby_players_updated.connect(func(_p): _update_visuals())
	
	if is_multiplayer_authority():
		if press_space_label: press_space_label.visible = false
		if is_occupied_label: is_occupied_label.visible = false
	else:
		if press_space_label: press_space_label.queue_free()
		if is_occupied_label: is_occupied_label.queue_free()

func _update_visuals() -> void:
	if not name_label: return
	var id = get_multiplayer_authority()
	var data = NetworkHandler.players.get(id, {})
	
	var txt = data.get("name", "Player %s" % id)
	if data.has("role"): txt += " (%s)" % data["role"]
	name_label.text = txt
	
	var col = data.get("color", Color.WHITE)
	# Si mort, on force transparence pour soi-même
	if is_dead: col.a = 0.5 
	anim.modulate = col
	name_label.modulate = col

func _connect_chest_signals() -> void:
	chest_area.area_entered.connect(_on_area_entered, 4)
	chest_area.area_exited.connect(_on_area_exited, 4)

func _process(_delta: float) -> void:
	if not is_inside_tree() or not multiplayer.has_multiplayer_peer(): return
	if not is_multiplayer_authority(): return
	
	# Interaction bloquée si mort
	if not is_dead:
		if not is_hidden:
			var overlap = chest_area.get_overlapping_areas().any(func(a): return a.has_meta("chest"))
			if not overlap:
				if is_in_chest:
					is_in_chest = false
					if press_space_label: press_space_label.visible = false
					if is_occupied_label: is_occupied_label.visible = false
			else:
				is_in_chest = true
		
		if Input.is_action_just_pressed("ui_accept"): _try_hide_or_open_chest()
		if Input.is_action_just_pressed("kill"): _try_kill_nearby_player()

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
	
	# Spectateur va plus vite
	var current_speed = speed * 1.5 if is_dead else speed
	
	velocity = move_dir * current_speed
	move_and_slide()
	
	if not is_dead: _handle_footsteps()

	rpc("_net_state", global_position, move_dir, last_move_dir)
	_update_animation()

func _handle_footsteps():
	if velocity.length() < 10.0 or not step_timer.is_stopped(): return
	if not level_tilemap: return

	var feet_pos = global_position + Vector2(0, 15)
	var map_pos = level_tilemap.local_to_map(feet_pos)
	var id1 = level_tilemap.get_cell_source_id(1, map_pos)
	var id0 = level_tilemap.get_cell_source_id(0, map_pos)
	
	var final = -1
	if id1 in [7]: final = id1 
	else: final = id0
	
	if final == -1: final = last_valid_tile_id
	else: last_valid_tile_id = final

	if final != -1:
		rpc("play_footstep_rpc", final)
		step_timer.start()

@rpc("call_local", "unreliable")
func play_footstep_rpc(tid: int):
	var s = sfx_wood if tid in [7] else sfx_grass
	if footstep_player.stream != s: footstep_player.stream = s
	footstep_player.pitch_scale = randf_range(0.9, 1.1)
	footstep_player.play()

func _try_hide_or_open_chest():
	if not is_multiplayer_authority(): return
	for a in chest_area.get_overlapping_areas():
		if a.has_meta("chest"):
			NetworkHandler.rpc_id(1, "request_player_hide_state", !is_hidden, a.global_position)
			break

@rpc("any_peer", "call_local", "unreliable")
func sync_player_visual_state(new_state: bool):
	is_hidden = new_state
	if chest_audio_player:
		chest_audio_player.pitch_scale = randf_range(0.9, 1.1)
		chest_audio_player.play()
	
	anim.visible = not new_state
	name_label.visible = not new_state
	collision_shape.disabled = new_state
	
	if is_multiplayer_authority():
		if new_state:
			if press_space_label: press_space_label.visible = false
			if is_occupied_label: is_occupied_label.visible = false
		else:
			is_in_chest = false
			for a in chest_area.get_overlapping_areas():
				if a.has_meta("chest"):
					is_in_chest = true
					NetworkHandler.rpc_id(1, "request_chest_occupancy_state", a.global_position)
					break
	
	if new_state: anim.stop()
	else: _update_animation()

@rpc("reliable")
func update_chest_ui(is_occupied: bool):
	if not is_multiplayer_authority(): return
	if is_in_chest and not is_hidden:
		if press_space_label: press_space_label.visible = !is_occupied
		if is_occupied_label: is_occupied_label.visible = is_occupied
	elif is_hidden:
		if press_space_label: press_space_label.visible = false
		if is_occupied_label: is_occupied_label.visible = false

@rpc("any_peer", "call_local", "unreliable")
func _net_state(pos: Vector2, dir: Vector2, last_dir: Vector2) -> void:
	if is_multiplayer_authority() or is_dead: return
	global_position = pos
	move_dir = dir
	last_move_dir = last_dir
	if not is_hidden: _update_animation()

func _update_animation() -> void:
	if is_dead:
		anim.stop() # Spectateur sans anim pour les autres
		return
	
	var c = move_dir if move_dir != Vector2.ZERO else last_move_dir
	if c.y > 0: anim.play("run-down" if move_dir != Vector2.ZERO else "idle-down")
	elif c.y < 0: anim.play("run-up" if move_dir != Vector2.ZERO else "idle-up")
	else: anim.play("run-left-right" if move_dir != Vector2.ZERO else "idle-left-right")
	anim.flip_h = c.x < 0

func _on_area_entered(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		is_in_chest = true 
		if not is_hidden and press_space_label: press_space_label.visible = true
		NetworkHandler.rpc_id(1, "request_chest_occupancy_state", a.global_position)

func _on_area_exited(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"): is_in_chest = false

func _try_kill_nearby_player() -> void:
	if not is_multiplayer_authority() or is_dead: return
	if not NetworkHandler.is_werewolf(get_multiplayer_authority()): return
	
	var root = get_tree().get_root().get_node_or_null("TestScene/Players")
	if not root: return
	for child in root.get_children():
		if child == self: continue
		if NetworkHandler.is_player_dead(child.get_multiplayer_authority()): continue
		if global_position.distance_to(child.global_position) <= 15.0:
			NetworkHandler.rpc_id(1, "request_kill_player", child.get_multiplayer_authority())
			break

@rpc("any_peer", "call_local", "reliable")
func play_death_animation() -> void:
	is_dead = true
	collision_shape.set_deferred("disabled", true)
	chest_area.monitoring = false
	if press_space_label: press_space_label.visible = false
	if is_occupied_label: is_occupied_label.visible = false
	
	if is_multiplayer_authority():
		anim.modulate.a = 0.5 
		anim.visible = true 
	else:
		anim.visible = false 
		name_label.visible = false
