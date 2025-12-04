extends Control

# Références aux éléments de l'interface
@onready var name_input := $UI_Container/NameInput
@onready var address_input := $UI_Container/AddressInput
@onready var error_label := $UI_Container/ErrorLabel

func _ready() -> void:
	# Connecter les signaux réseau pour gérer les événements de connexion
	get_tree().get_multiplayer().connected_to_server.connect(_on_connected_ok)
	NetworkHandler.connection_failed_ui.connect(_on_failed)

# Créer un serveur et héberger une partie
func _on_HostButton_pressed() -> void:
	NetworkHandler.nickname = _get_player_name()
	NetworkHandler.host()
	_go_to_lobby()

# Rejoindre un serveur existant
func _on_JoinButton_pressed() -> void:
	NetworkHandler.nickname = _get_player_name()
	var ip = address_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	NetworkHandler.join(ip)

# Appelé quand la connexion au serveur réussit
func _on_connected_ok() -> void:
	_go_to_lobby()

# Affiche un message d'erreur en cas d'échec de connexion
func _on_failed() -> void:
	error_label.text = "Connection Failed"

# Change de scène vers le lobby
func _go_to_lobby() -> void:
	get_tree().change_scene_to_file("res://lobby.tscn")

# Récupère le nom du joueur depuis l'input, ou retourne "Player" par défaut
func _get_player_name() -> String:
	var name = name_input.text.strip_edges()
	return "Player" if name == "" else name
