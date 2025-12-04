extends Control

signal go_to_menu

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var menu_button: TextureButton = $VBoxContainer/MenuButton

func _ready() -> void:
	visible = false
	menu_button.pressed.connect(func(): go_to_menu.emit())

func show_victory(winner_role: String):
	visible = true
	# Convertir "werewolf" en "WEREWOLF WON!"
	if winner_role == "LOUPS-GAROUS":
		title_label.text = "WEREWOLVES WON !"
		title_label.modulate = Color.RED
	else:
		title_label.text = "VILLAGERS WON !"
		title_label.modulate = Color.GREEN

func show_disconnect():
	visible = true
	title_label.text = "HOST DISCONNECTED"
	title_label.modulate = Color.ORANGE
