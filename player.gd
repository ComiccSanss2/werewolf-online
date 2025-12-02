extends CharacterBody2D

#############################################################
#                  VARIABLES EXISTANTES
#############################################################

@export var speed := 75
@onready var anim := $AnimatedSprite2D
@onready var sprite := $AnimatedSprite2D
@onready var name_label := $NameLabel
@onready var collider := $CollisionShape2D
@onready var detector := $AreaDetector
@onready var press_label := $PressSpaceLabel

var last_direction := Vector2.DOWN
var network_pos := Vector2.ZERO

var inside_chest := false
var can_interact := false
var current_chest: Area2D = null
var saved_speed := 75


#############################################################
#                  CAMERA MULTI
#############################################################

func _enter_tree():
	if is_multiplayer_authority():
		$Camera2D.enabled = true
		$Camera2D.make_current()


func _ready():
	press_label.visible = false
	saved_speed = speed

	detector.area_entered.connect(_on_area_entered)
	detector.area_exited.connect(_on_area_exited)


#############################################################
#                  MOUVEMENT
#############################################################

func _physics_process(delta):
	if inside_chest:
		velocity = Vector2.ZERO
		return

	var input_dir := Vector2.ZERO

	if is_multiplayer_authority():
		if Input.is_action_pressed("ui_up"):
			input_dir.y -= 1
		if Input.is_action_pressed("ui_down"):
			input_dir.y += 1
		if Input.is_action_pressed("ui_left"):
			input_dir.x -= 1
		if Input.is_action_pressed("ui_right"):
			input_dir.x += 1

		input_dir = input_dir.normalized()

		if input_dir != Vector2.ZERO:
			last_direction = input_dir

		velocity = input_dir * speed
		move_and_slide()

		_update_animation(input_dir)

		rpc("sync_direction", input_dir, last_direction)
		rpc("sync_position", global_position)

	else:
		global_position = global_position.lerp(network_pos, 0.25)



#############################################################
#                  ANIMATIONS
#############################################################

func _update_animation(dir):
	if dir == Vector2.ZERO:
		if abs(last_direction.x) > abs(last_direction.y):
			anim.play("idle-left-right")
			anim.flip_h = last_direction.x < 0
		else:
			anim.play("idle-down" if last_direction.y > 0 else "idle-up")
	else:
		if abs(dir.x) > abs(dir.y):
			anim.play("run-left-right")
			anim.flip_h = dir.x < 0
		else:
			anim.play("run-down" if dir.y > 0 else "run-up")


#############################################################
#                  SYNC MULTI
#############################################################

@rpc("any_peer", "unreliable")
func sync_position(pos):
	if !is_multiplayer_authority():
		network_pos = pos

@rpc("any_peer", "unreliable")
func sync_direction(dir, last_dir):
	if !is_multiplayer_authority():
		last_direction = last_dir
		_update_animation(dir)



#############################################################
#                INTERACTION AVEC COFFRE
#############################################################

func _process(delta):
	var local_id = get_tree().get_multiplayer().get_unique_id()
	var my_id = name.to_int()

	if my_id == local_id and can_interact and Input.is_action_just_pressed("interact"):
		rpc_id(1, "request_toggle_chest", get_path(), current_chest.get_path())


@rpc("any_peer", "reliable")
func request_toggle_chest(player_path, chest_path):
	if get_tree().get_multiplayer().is_server():
		rpc("toggle_chest_state", player_path, chest_path)


@rpc("any_peer", "reliable")
func toggle_chest_state(player_path, chest_path):
	var player = get_node(player_path)
	var chest = get_node(chest_path)

	var occupied = chest.get_meta("occupied")

	# entrer
	if !occupied and !player.inside_chest:
		chest.set_meta("occupied", true)
		player.inside_chest = true

		player.sprite.visible = false
		player.name_label.visible = false
		player.collider.disabled = true

		player.speed = 0
		player.velocity = Vector2.ZERO

		player.global_position = chest.global_position

	# sortir
	elif occupied and player.inside_chest:
		chest.set_meta("occupied", false)
		player.inside_chest = false

		player.sprite.visible = true
		player.name_label.visible = true
		player.collider.disabled = false

		player.speed = player.saved_speed
		player.global_position = chest.global_position + Vector2(0, 16)



#############################################################
#                     DÉTECTION DES ZONES
#############################################################

func _on_area_entered(area):
	if area.has_meta("chest") and !inside_chest:
		current_chest = area
		can_interact = true
		press_label.visible = true

func _on_area_exited(area):
	if area == current_chest:
		current_chest = null
		can_interact = false
		press_label.visible = false
