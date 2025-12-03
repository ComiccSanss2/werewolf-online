extends Control

@onready var name_input := $NameInput
@onready var address_input := $AddressInput
@onready var error_label := $ErrorLabel 

func _ready() -> void:
	get_tree().get_multiplayer().connected_to_server.connect(_on_connected_ok)
	NetworkHandler.connection_failed_ui.connect(_on_failed)

func _on_HostButton_pressed() -> void:
	
	var name: String = name_input.text.strip_edges()
	if name == "":
		name = "Player"
		
	NetworkHandler.nickname = name
	NetworkHandler.host()
	_go_to_lobby()


func _on_JoinButton_pressed() -> void:
	
	var name: String = name_input.text.strip_edges()
	if name == "":
		name = "Player"

	var ip: String = address_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1" 
		
	NetworkHandler.nickname = name
	NetworkHandler.join(ip)


func _on_connected_ok() -> void:
	_go_to_lobby()

func _on_failed() -> void:
	error_label.text = "Connessione fallita. Controlla IP/Porta."

func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://lobby.tscn")
