extends Control

# Limite de caractères pour le nom
const MAX_NAME_LENGTH = 12

@onready var name_input := $UI_Container/NameInput
@onready var address_input := $UI_Container/AddressInput
@onready var error_label := $UI_Container/ErrorLabel
@onready var host_button := $UI_Container/HostButton
@onready var join_button := $UI_Container/JoinButton

# --- AUDIO ---
@onready var sfx_player: AudioStreamPlayer = $SFX_Player

var sound_click = preload("res://assets/sfx/clickbutton.wav")
var sound_type = preload("res://assets/sfx/typesound.wav")

func _ready() -> void:
	# 1. SETUP LOGIQUE
	if name_input:
		name_input.max_length = MAX_NAME_LENGTH
		name_input.text_changed.connect(_on_name_changed)
	
	if error_label:
		error_label.text = ""
	
	# Connexions Réseau
	get_tree().get_multiplayer().connected_to_server.connect(_on_connected_ok)
	NetworkHandler.connection_failed_ui.connect(_on_failed)

	_setup_juice()

func _setup_juice() -> void:
	var buttons = [host_button, join_button]
	
	for btn in buttons:
		btn.pivot_offset = btn.size / 2
		
		# Son au clic
		btn.pressed.connect(func(): _play_sound(sound_click))
		
		# Son au survol (Pitch légèrement plus aigu)
		
		# Animation "Pop" (Tween)
		btn.mouse_entered.connect(func(): _animate_button(btn, 0.55)) # Grossit un peu (base 0.5 -> 0.55)
		btn.mouse_exited.connect(func(): _animate_button(btn, 0.5))   # Revient à la normale

	# --- INPUTS (Bruit de clavier) ---
	var inputs = [name_input, address_input]
	
	for inp in inputs:
		# Son à chaque lettre tapée
		inp.text_changed.connect(func(_t): _play_typing_sound())

# --- FONCTIONS D'ANIMATION & SON ---

func _play_sound(stream: AudioStream, pitch: float = 1.0):
	if sfx_player:
		sfx_player.stream = stream
		sfx_player.pitch_scale = pitch
		sfx_player.play()

func _play_typing_sound():
	# Variation aléatoire du pitch pour faire réaliste
	_play_sound(sound_type, randf_range(0.9, 1.1))

func _animate_button(btn: Control, target_scale: float):
	var tween = create_tween()
	# Animation fluide et élastique (Ease Out Elastic ou Cubic)
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# --- LOGIQUE RÉSEAU & VALIDATION (Ton code original) ---

func _on_name_changed(_new_text: String) -> void:
	error_label.text = ""

func _on_HostButton_pressed() -> void:
	if not _validate_name(): return
	NetworkHandler.nickname = _get_player_name()
	NetworkHandler.host()
	_go_to_lobby()

func _on_JoinButton_pressed() -> void:
	if not _validate_name(): return
	NetworkHandler.nickname = _get_player_name()
	var ip = address_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1" # Localhost par défaut
	NetworkHandler.join(ip)

func _validate_name() -> bool:
	var name = name_input.text.strip_edges()
	# Le Input a déjà un max_length, mais on double check ici
	if name.length() > MAX_NAME_LENGTH:
		error_label.text = "Nom trop long !"
		return false
	return true

func _on_connected_ok() -> void:
	_go_to_lobby()

func _on_failed() -> void:
	error_label.text = "Échec de connexion !"
	# Petit effet visuel : texte rouge qui tremble (optionnel)
	var tween = create_tween()
	error_label.modulate = Color.RED
	tween.tween_property(error_label, "position:x", error_label.position.x + 5, 0.05)
	tween.tween_property(error_label, "position:x", error_label.position.x - 5, 0.05)
	tween.tween_property(error_label, "position:x", error_label.position.x, 0.05)

func _go_to_lobby() -> void:

	await get_tree().create_timer(0.15).timeout
	
	get_tree().change_scene_to_file("res://lobby.tscn")

func _get_player_name() -> String:
	var name = name_input.text.strip_edges()
	if name == "":
		return "Player"
	return name
