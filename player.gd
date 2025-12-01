extends CharacterBody2D

@export var speed := 200
@onready var anim = $AnimatedSprite2D

var last_direction := Vector2.DOWN  # pour choisir l'idle correct

func _ready():
	if is_multiplayer_authority():
		modulate = Color(0.85, 1, 0.85)  # local = vert clair
	else:
		modulate = Color(1, 0.85, 0.85)  # autres = rouge clair


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

	# sauvegarde la dernière direction (pour idle)
	if input_dir != Vector2.ZERO:
		last_direction = input_dir

	velocity = input_dir * speed
	move_and_slide()

	_update_animation(input_dir)

	# Sync réseau
	rpc("sync_position", global_position)


# ===========================
#     ANIMATIONS
# ===========================

func _update_animation(dir: Vector2):
	if dir == Vector2.ZERO:
		# IDLE
		if abs(last_direction.x) > abs(last_direction.y):
			anim.play("idle-left-right")
			anim.flip_h = last_direction.x < 0
		else:
			if last_direction.y > 0:
				anim.play("idle-down")
			else:
				anim.play("idle-up")
	else:
		# RUN
		if abs(dir.x) > abs(dir.y):
			anim.play("run-left-right")
			anim.flip_h = dir.x < 0
		else:
			if dir.y > 0:
				anim.play("run-down")
			else:
				anim.play("run-up")


# ===========================
#     NETWORK SYNC
# ===========================

@rpc("any_peer", "unreliable")
func sync_position(pos: Vector2):
	if !is_multiplayer_authority():
		global_position = pos
