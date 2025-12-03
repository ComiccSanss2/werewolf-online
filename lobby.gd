extends Control

@onready var players_list = $CanvasLayer/VBoxContainer
@onready var start_button = $CanvasLayer/ButtonStart
@onready var status_label = $CanvasLayer/LabelStatus
@onready var color_button = $CanvasLayer/ButtonColor
@onready var color_window = $ColorWindow

# Tableau de couleurs prédéfinies si tu veux t’en servir plus tard
var predefined_colors = [
	Color.RED,
	Color.GREEN,
	Color.BLUE,
	Color.YELLOW,
	Color.CYAN,
	Color.MAGENTA,
	Color.ORANGE,
	Color.PURPLE,
	Color.WHITE,
	Color.BLACK
]

###################################################
# READY
###################################################

func _ready():
	var mp = get_tree().get_multiplayer()

	# Connect network signals
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(_on_failed)

	# Connect bouton de sélection (tous les enfants de la grid)
	for btn in color_window.get_node("GridContainer").get_children():
		btn.pressed.connect(_on_color_selected.bind(btn.self_modulate))

	###################################################
	# HOST INITIALIZATION
	###################################################
	if mp.is_server():
		start_button.visible = true
		start_button.disabled = false

		color_button.visible = true
		color_button.disabled = false

		color_window.visible = false
		
		var host_id = mp.get_unique_id()

		# Save host pseudo
		Network.player_names[host_id] = Network.nickname

		# Display host
		_add_player(host_id)
		_update_player_label(host_id, Network.nickname)

	###################################################
	# CLIENT INITIALIZATION
	###################################################
	else:
		start_button.visible = false
		color_button.visible = true



###################################################
# CLIENT CONNECTED
###################################################

func _on_connected():
	var mp = get_tree().get_multiplayer()
	var my_id = mp.get_unique_id()

	print("CLIENT: connected — sending nickname")

	_add_player(my_id)
	_update_player_label(my_id, Network.nickname)

	rpc_id(1, "register_name_request", Network.nickname)

	status_label.text = "Connected. Waiting for players..."


###################################################
# SERVER RECEIVES NAME
###################################################

@rpc("any_peer")
func register_name_request(name: String):
	var mp = get_tree().get_multiplayer()

	if mp.is_server():
		var sender_id = mp.get_remote_sender_id()
		Network.player_names[sender_id] = name

		print("SERVER REGISTER:", sender_id, name)

		rpc("register_name_broadcast", sender_id, name)

		var host_id = mp.get_unique_id()
		rpc_id(sender_id, "register_name_broadcast", host_id, Network.player_names[host_id])



###################################################
# COLOR SELECTION (NEW SYSTEM)
###################################################

func _on_button_color_pressed():
	color_window.popup_centered()
	color_window.visible = true
func _on_color_selected(color: Color):
	var mp = get_tree().get_multiplayer()
	var my_id = mp.get_unique_id()

	# Save
	Network.player_colors[my_id] = color

	# Update local UI
	_update_player_color(my_id, color)

	# Sync others
	rpc("update_player_color_remote", my_id, color)

	color_window.hide()


@rpc("any_peer")
func update_player_color_remote(peer_id: int, color: Color):
	Network.player_colors[peer_id] = color
	_update_player_color(peer_id, color)



func _update_player_color(peer_id: int, color: Color):
	if players_list.has_node(str(peer_id)):
		var label = players_list.get_node(str(peer_id))
		label.add_theme_color_override("font_color", color)



###################################################
# NAME BROADCAST
###################################################

@rpc("any_peer")
func register_name_broadcast(peer_id: int, name: String):
	print("BROADCAST:", peer_id, name)

	Network.player_names[peer_id] = name

	_add_player(peer_id)
	_update_player_label(peer_id, name)



###################################################
# CONNECT / DISCONNECT
###################################################

func _on_player_connected(peer_id):
	print("PLAYER CONNECTED:", peer_id)
	_add_player(peer_id) 

func _on_player_disconnected(peer_id):
	print("PLAYER DISCONNECTED:", peer_id)

	if players_list.has_node(str(peer_id)):
		players_list.get_node(str(peer_id)).queue_free()



###################################################
# UI MANAGEMENT
###################################################

func _add_player(peer_id):
	if !players_list.has_node(str(peer_id)):
		var label = Label.new()
		label.name = str(peer_id)
		label.text = "Loading..."
		players_list.add_child(label)

	# Update right away
	var pseudo = Network.player_names.get(peer_id, "Loading...")
	players_list.get_node(str(peer_id)).text = pseudo + " (" + str(peer_id) + ")"

func _update_player_label(peer_id, name):
	await get_tree().process_frame

	if !players_list.has_node(str(peer_id)):
		_add_player(peer_id)

	players_list.get_node(str(peer_id)).text = name + " (" + str(peer_id) + ")"



###################################################
# START GAME
###################################################

func _on_ButtonStart_pressed():
	var mp = get_tree().get_multiplayer()
	if !mp.is_server():
		return

	print("HOST: starting game")

	rpc("start_game_remote")
	_start_game()

@rpc("any_peer", "reliable")
func start_game_remote():
	_start_game()

func _start_game():
	get_tree().change_scene_to_file("res://test_scene.tscn")



###################################################
# FAILED
###################################################

func _on_failed():
	status_label.text = "Connection failed"
