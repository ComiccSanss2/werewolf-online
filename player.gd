extends CharacterBody2D

@export var speed := 75
@onready var anim := $AnimatedSprite2D

var player_id := 0
var last_direction := Vector2.DOWN
var network_pos := Vector2.ZERO


func _enter_tree():
	if is_multiplayer_authority():
		$Camera2D.enabled = true
		$Camera2D.make_current()
	else:
		$Camera2D.enabled = false


func _ready():
	player_id = get_multiplayer_authority()
	
	# Appliquer la couleur stockée dans l'Autoload (Network)
	_apply_color()

func _apply_color(): # <--- NOUVELLE FONCTION
	# Récupère la couleur de l'Autoload en utilisant l'ID du joueur
	var color_to_apply = Network.player_colors.get(player_id, Color.WHITE)
	anim.modulate = color_to_apply

func _physics_process(delta):
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



func _update_animation(dir: Vector2):
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


@rpc("any_peer", "unreliable")
func sync_position(pos: Vector2):
	if !is_multiplayer_authority():
		network_pos = pos


@rpc("any_peer", "unreliable")
func sync_direction(dir: Vector2, last_dir: Vector2):
	if !is_multiplayer_authority():
		last_direction = last_dir
		_update_animation(dir)
