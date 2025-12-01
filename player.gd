extends CharacterBody2D

@export var speed := 75
@onready var anim = $AnimatedSprite2D

var last_direction := Vector2.DOWN

func _enter_tree():
	if is_multiplayer_authority():
		$Camera2D.enabled = true

func _ready():
	if is_multiplayer_authority():
		$Camera2D.enabled = true
	else:
		$Camera2D.enabled = false




func _physics_process(delta):
	if not is_multiplayer_authority():
		return

	var input_dir = Vector2.ZERO

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

	rpc("sync_position", global_position)


func _update_animation(dir: Vector2):
	if dir == Vector2.ZERO:
		if abs(last_direction.x) > abs(last_direction.y):
			anim.play("idle-left-right")
			anim.flip_h = last_direction.x < 0
		else:
			if last_direction.y > 0:
				anim.play("idle-down")
			else:
				anim.play("idle-up")
	else:
		if abs(dir.x) > abs(dir.y):
			anim.play("run-left-right")
			anim.flip_h = dir.x < 0
		else:
			if dir.y > 0:
				anim.play("run-down")
			else:
				anim.play("run-up")


@rpc("any_peer", "unreliable")
func sync_position(pos: Vector2):
	if !is_multiplayer_authority():
		global_position = pos
