extends CharacterBody2D

@export var speed = 75.0

var is_in_chest = false
var move_dir = Vector2.ZERO
var last_move_dir = Vector2.DOWN
var is_hidden = false
var is_dead = false

var is_stunned = false
var stun_timer = 0.0
@onready var stun_visual = $StunVisual 

@onready var anim = $AnimatedSprite2D
@onready var name_label = $NameLabel
@onready var camera = $Camera2D
@onready var chest_area = $ChestDetector
@onready var collision_shape = $CollisionShape2D
@onready var press_space_label = $PressSpaceLabel
@onready var is_occupied_label = $IsOccupiedLabel

@onready var footstep_player: AudioStreamPlayer2D = $FootstepPlayer
@onready var chest_audio_player: AudioStreamPlayer2D = $ChestAudioPlayer
@onready var step_timer: Timer = $StepTimer

const KILL_RANGE = 15.0
const REVIVE_RANGE = 25.0
const HIDE_DURATION = 10.0
const HIDE_COOLDOWN = 10.0
# Augmentation de la distance de report pour faciliter l'action
const REPORT_RANGE = 60.0 
const STUN_RADIUS_ON_EXIT = 60.0 
const STUN_DURATION = 2.5        

var hide_timer = 0.0
var cooldown_timer = 0.0
var can_hide = true
var cooldown_label: Label
var hide_label: Label

var nearby_corpse = false

var sfx_grass = preload("res://sfx_grass.tres")
var sfx_wood = preload("res://sfx_wood.tres")
var level_tilemap: TileMap = null
var last_valid_tile_id: int = 0

func _my_id() -> int: return get_multiplayer_authority()
func _is_authority() -> bool: return is_multiplayer_authority()
func _get_players_root(): return get_tree().get_root().get_node_or_null("TestScene/Players")

func _ready() -> void:
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		set_process_mode(PROCESS_MODE_DISABLED)
		return
	
	camera.enabled = _is_authority()
	level_tilemap = get_tree().get_root().get_node_or_null("TestScene/TileMap_Interactions/TileMap")
	chest_area.area_entered.connect(_on_area_entered, 4)
	chest_area.area_exited.connect(_on_area_exited, 4)
	
	if stun_visual: stun_visual.visible = false
	
	_update_visuals()
	NetworkHandler.lobby_players_updated.connect(func(_p): _update_visuals())
	
	if _is_authority():
		_hide_labels()
	else:
		if press_space_label: press_space_label.queue_free()
		if is_occupied_label: is_occupied_label.queue_free()

func _hide_labels() -> void:
	if is_instance_valid(press_space_label): press_space_label.visible = false
	if is_instance_valid(is_occupied_label): is_occupied_label.visible = false

func _create_chest_label(color: Color):
	var chest = _find_chest_area()
	if not chest: return null
	var label = Label.new()
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.scale = Vector2(0.5, 0.5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.anchors_preset = Control.PRESET_CENTER_TOP
	label.position = Vector2(0, -30)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	chest.add_child(label)
	return label

func _show_cooldown_on_chest() -> void:
	if not cooldown_label: cooldown_label = _create_chest_label(Color.RED)
	if is_instance_valid(cooldown_label): cooldown_label.text = "%.0fs" % cooldown_timer

func _remove_cooldown_label() -> void:
	if cooldown_label and is_instance_valid(cooldown_label): cooldown_label.queue_free()
	cooldown_label = null

func _create_hide_label() -> void:
	if not hide_label: hide_label = _create_chest_label(Color.YELLOW)

func _update_hide_label() -> void:
	if is_instance_valid(hide_label): hide_label.text = "%.0fs" % (HIDE_DURATION - hide_timer)

func _remove_hide_label() -> void:
	if hide_label and is_instance_valid(hide_label): hide_label.queue_free()
	hide_label = null

# --- REPORT ---
func _show_report_label() -> void:
	var scene = get_tree().get_root().get_node_or_null("TestScene")
	if scene and scene.has_method("set_report_label_visible"):
		scene.set_report_label_visible(true)

func _remove_report_label() -> void:
	var scene = get_tree().get_root().get_node_or_null("TestScene")
	if scene and scene.has_method("set_report_label_visible"):
		scene.set_report_label_visible(false)

func _try_report_body() -> void:
	if not nearby_corpse or is_dead: return
	rpc_id(1, "report_body_to_server")

@rpc("any_peer", "call_local", "reliable")
func report_body_to_server():
	if not multiplayer.is_server(): return
	var scene = get_tree().get_root().get_node_or_null("TestScene")
	if scene and scene.has_method("trigger_emergency_meeting"):
		scene.trigger_emergency_meeting()

func _update_visuals() -> void:
	if not name_label: return
	var data = NetworkHandler.players.get(_my_id(), {})
	var text = data.get("name", "Player %s" % _my_id())
	if _is_authority() and data.has("role"): 
		text += " (%s)" % data["role"]
	name_label.text = text
	var color = data.get("color", Color.WHITE)
	if is_dead: color.a = 0.5 
	anim.modulate = color
	name_label.modulate = color

func _process(delta: float) -> void:
	if not is_inside_tree() or not multiplayer.has_multiplayer_peer(): return
	
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0: receive_stun(0)
	
	if not _is_authority(): return
	
	# BLOQUAGE GAMEPLAY SI INTERMISSION/VOTE/FIN
	if not NetworkHandler.is_gameplay_active:
		velocity = Vector2.ZERO
		rpc("_net_state", global_position, Vector2.ZERO, last_move_dir)
		_update_animation()
		return
	
	if NetworkHandler.is_player_dead(_my_id()): is_dead = true
	
	if is_stunned:
		velocity = Vector2.ZERO
		rpc("_net_state", global_position, Vector2.ZERO, last_move_dir)
		_update_animation()
		return

	if not is_dead:
		_update_timers(delta)
		_update_chest_state()
		_update_corpse_state()
		_handle_inputs()
	else:
		if nearby_corpse:
			nearby_corpse = false
			_remove_report_label()
	
	if is_hidden:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)
	move_dir = input.normalized()
	if move_dir != Vector2.ZERO: last_move_dir = move_dir

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

func _update_timers(delta: float) -> void:
	if is_hidden:
		hide_timer += delta
		_update_hide_label()
		if hide_timer >= HIDE_DURATION: _try_hide_or_open_chest()
	
	if not can_hide:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			can_hide = true
			cooldown_timer = 0
			_remove_cooldown_label()

func _update_chest_state() -> void:
	if is_hidden: return
	var has_chest = chest_area.get_overlapping_areas().any(func(a): return a.has_meta("chest"))
	if not has_chest and is_in_chest:
		is_in_chest = false
		_hide_labels()
		_remove_cooldown_label()
	elif has_chest:
		is_in_chest = true
		if not can_hide: _show_cooldown_on_chest()
		var chest = _find_chest_area()
		if chest: NetworkHandler.rpc_id(1, "request_chest_occupancy_state", chest.global_position)
		if is_instance_valid(press_space_label): press_space_label.visible = false

func _update_corpse_state() -> void:
	var scene = get_tree().get_root().get_node_or_null("TestScene")
	if not scene: return
	var bodies = scene.get_node_or_null("DeadBodies")
	if not bodies: return
	
	var found_corpse = false
	for corpse in bodies.get_children():
		if global_position.distance_to(corpse.global_position) <= REPORT_RANGE:
			found_corpse = true
			break
	
	if found_corpse and not nearby_corpse:
		nearby_corpse = true
		_show_report_label()
	elif not found_corpse and nearby_corpse:
		nearby_corpse = false
		_remove_report_label()

func _handle_inputs() -> void:
	if not NetworkHandler.is_gameplay_active: return
	if Input.is_action_just_pressed("ui_accept"): _try_hide_or_open_chest()
	if Input.is_action_just_pressed("kill"): _try_kill_nearby_player()
	if Input.is_action_just_pressed("revive"): _try_revive_nearby_player()
	if Input.is_action_just_pressed("report"): _try_report_body()

func _find_chest_area():
	for area in chest_area.get_overlapping_areas():
		if area.has_meta("chest"): return area
	return null

func _try_hide_or_open_chest():
	if is_hidden:
		NetworkHandler.rpc_id(1, "request_player_hide_state", false, Vector2.ZERO)
		NetworkHandler.rpc_id(1, "request_area_stun", global_position, STUN_RADIUS_ON_EXIT, STUN_DURATION, _my_id())
		cooldown_timer = HIDE_COOLDOWN
		can_hide = false
		hide_timer = 0
		_remove_hide_label()
		return
	
	if not can_hide: return
	
	var chest = _find_chest_area()
	if chest:
		NetworkHandler.rpc_id(1, "request_player_hide_state", true, chest.global_position)
		hide_timer = 0
		_create_hide_label()

func receive_stun(duration: float):
	if duration > 0:
		is_stunned = true
		stun_timer = duration
		if stun_visual:
			stun_visual.visible = true
			stun_visual.play("default")
	else:
		is_stunned = false
		stun_timer = 0
		if stun_visual:
			stun_visual.visible = false
			stun_visual.stop()

@rpc("any_peer", "call_local", "unreliable")
func sync_player_visual_state(new_state: bool):
	is_hidden = new_state
	if chest_audio_player:
		chest_audio_player.pitch_scale = randf_range(0.9, 1.1)
		chest_audio_player.play()
	
	if is_instance_valid(anim): anim.visible = not new_state
	if is_instance_valid(name_label): name_label.visible = not new_state
	if is_instance_valid(collision_shape): collision_shape.disabled = new_state
	
	if stun_visual and new_state: stun_visual.visible = false
	
	if new_state:
		if _is_authority(): _hide_labels()
		anim.stop()
	else:
		if _is_authority():
			var chest = _find_chest_area()
			if chest:
				is_in_chest = true
				NetworkHandler.rpc_id(1, "request_chest_occupancy_state", chest.global_position)
			else:
				is_in_chest = false
		_update_animation()

@rpc("reliable")
func update_chest_ui(is_occupied: bool):
	if not _is_authority() or is_hidden or not is_in_chest:
		if _is_authority(): _hide_labels()
		return
	if is_instance_valid(press_space_label): press_space_label.visible = not is_occupied
	if is_instance_valid(is_occupied_label): is_occupied_label.visible = is_occupied

@rpc("any_peer", "call_local", "unreliable")
func _net_state(pos: Vector2, dir: Vector2, last_dir: Vector2) -> void:
	if _is_authority() or is_dead: return
	global_position = pos
	move_dir = dir
	last_move_dir = last_dir
	if not is_hidden: _update_animation()

func _update_animation() -> void:
	if is_dead:
		anim.stop()
		return
	
	var dir = move_dir if move_dir != Vector2.ZERO else last_move_dir
	var prefix = "run" if move_dir != Vector2.ZERO else "idle"
	var suffix = "-down" if dir.y > 0 else ("-up" if dir.y < 0 else "-left-right")
	anim.play(prefix + suffix)
	anim.flip_h = dir.x < 0

func _on_area_entered(area: Area2D) -> void:
	if not _is_authority() or not area.has_meta("chest"): return
	is_in_chest = true
	if not is_hidden and is_instance_valid(press_space_label): press_space_label.visible = true
	NetworkHandler.rpc_id(1, "request_chest_occupancy_state", area.global_position)

func _on_area_exited(area: Area2D) -> void:
	if _is_authority() and area.has_meta("chest"): is_in_chest = false

func _find_nearby_player(max_range: float, must_be_dead: bool):
	var players_root = _get_players_root()
	if not players_root: return null
	
	for child in players_root.get_children():
		if child == self: continue
		var target_id = child.get_multiplayer_authority()
		var target_dead = NetworkHandler.is_player_dead(target_id)
		if target_dead != must_be_dead: continue
		if global_position.distance_to(child.global_position) <= max_range:
			return target_id
	return null

func _try_action_on_nearby(action: String, max_range: float, target_dead: bool, role_check: Callable):
	if NetworkHandler.is_player_dead(_my_id()) or not role_check.call(_my_id()): return
	var target = _find_nearby_player(max_range, target_dead)
	if target != null: NetworkHandler.rpc_id(1, action, target)

func _try_kill_nearby_player() -> void:
	_try_action_on_nearby("request_kill_player", KILL_RANGE, false, NetworkHandler.is_werewolf)

func _try_revive_nearby_player() -> void:
	_try_action_on_nearby("request_revive_player", REVIVE_RANGE, true, NetworkHandler.is_sorciere)

@rpc("any_peer", "call_local", "reliable")
func play_death_animation() -> void:
	is_dead = true
	receive_stun(0)
	collision_shape.set_deferred("disabled", true)
	chest_area.monitoring = false
	_hide_labels()
	
	if _is_authority():
		anim.modulate.a = 0.5
		anim.visible = true
	else:
		anim.visible = false
		name_label.visible = false

@rpc("any_peer", "call_local", "reliable")
func revive_character() -> void:
	is_dead = false
	collision_shape.disabled = false
	chest_area.monitoring = true
	anim.modulate.a = 1.0
	anim.visible = true
	name_label.visible = true
	anim.play("idle-down")
	
	

# RPC: Force la position du joueur (appelé par le serveur après un vote)
@rpc("call_local", "reliable")
func force_teleport(new_pos: Vector2):
	global_position = new_pos
	velocity = Vector2.ZERO
	move_dir = Vector2.ZERO
	if is_multiplayer_authority():
		rpc("_net_state", new_pos, Vector2.ZERO, last_move_dir)
