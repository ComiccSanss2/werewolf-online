extends Label

@export var pulse_speed: float = 2.0
@export var rainbow_speed: float = 0.5
@export var scale_amount: float = 1.1 # Grossissement max (1.1 = +10%)

var base_scale: Vector2
var time: float = 0.0

func _ready() -> void:
	# On sauvegarde la taille de base
	base_scale = scale
	# Important pour que le zoom se fasse depuis le centre du texte
	pivot_offset = size / 2

func _process(delta: float) -> void:
	time += delta
	
	# 1. Effet Arc-en-ciel (Hue Shift)
	# On utilise from_hsv pour créer une couleur en changeant la teinte (Hue) selon le temps
	# Hue (0-1) qui boucle
	var hue = fmod(time * rainbow_speed, 1.0)
	# Saturation 0.6 (pas trop flash), Valeur 1.0 (lumineux)
	modulate = Color.from_hsv(hue, 0.6, 1.0)
	
	# 2. Effet Pulse (Sinusoidale)
	# Sinus varie de -1 à 1. On le map pour avoir un facteur de scale doux.
	var pulse = (sin(time * pulse_speed) + 1.0) / 2.0 # Devient 0 à 1
	var current_scale = lerp(1.0, scale_amount, pulse)
	
	scale = base_scale * current_scale
