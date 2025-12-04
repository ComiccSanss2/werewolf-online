extends Control

# Limite de caractères pour le nom
const MAX_NAME_LENGTH = 12

# Références aux éléments de l'interface
@onready var name_input := $UI_Container/NameInput
@onready var address_input := $UI_Container/AddressInput
@onready var error_label := $UI_Container/ErrorLabel

func _ready() -> void:
	# Configure la limite de caractères sur l'input
	if name_input:
		name_input.max_length = MAX_NAME_LENGTH
		name_input.text_changed.connect(_on_name_changed)
	
	# Cache le message d'erreur au départ
	if error_label:
		error_label.text = ""
	
	# Connecter les signaux réseau pour gérer les événements de connexion
	get_tree().get_multiplayer().connected_to_server.connect(_on_connected_ok)
	NetworkHandler.connection_failed_ui.connect(_on_failed)

# Efface l'erreur quand l'utilisateur tape
func _on_name_changed(_new_text: String) -> void:
	error_label.text = ""

# Créer un serveur et héberger une partie
func _on_HostButton_pressed() -> void:
	if not _validate_name(): return
	NetworkHandler.nickname = _get_player_name()
	NetworkHandler.host()
	_go_to_lobby()

# Rejoindre un serveur existant
func _on_JoinButton_pressed() -> void:
	if not _validate_name(): return
	NetworkHandler.nickname = _get_player_name()
	var ip = address_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	NetworkHandler.join(ip)

# Valide le nom avant de continuer
func _validate_name() -> bool:
	var name = name_input.text.strip_edges()
	if name.length() > MAX_NAME_LENGTH:
		error_label.text = "Nom trop long (max %d caractères)" % MAX_NAME_LENGTH
		return false
	return true

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
	if name == "":
		return "Player"
	# Limite à MAX_NAME_LENGTH caractères
	if name.length() > MAX_NAME_LENGTH:
		name = name.substr(0, MAX_NAME_LENGTH)
	return name
