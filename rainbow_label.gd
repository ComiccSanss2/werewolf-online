extends Label

@export var pulse_speed: float = 2.0
@export var rainbow_speed: float = 0.5
@export var scale_amount: float = 1.1 # Grossissement max (1.1 = +10%)

var base_scale: Vector2
var time: float = 0.0

func _ready() -> void:
	base_scale = scale
	pivot_offset = size / 2

func _process(delta: float) -> void:
	time += delta
	

	var hue = fmod(time * rainbow_speed, 1.0)
	modulate = Color.from_hsv(hue, 0.6, 1.0)

	var pulse = (sin(time * pulse_speed) + 1.0) / 2.0 # Devient 0 à 1
	var current_scale = lerp(1.0, scale_amount, pulse)
	
	scale = base_scale * current_scale
