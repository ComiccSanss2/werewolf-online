extends Control

@onready var players_list = $CanvasLayer/VBoxContainer
@onready var start_button = $CanvasLayer/ButtonStart
@onready var status_label = $CanvasLayer/LabelStatus


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

	###################################################
	# HOST INITIALIZATION
	###################################################
	if mp.is_server():
		start_button.visible = true
		start_button.disabled = false

		var host_id = mp.get_unique_id()

		# Save host pseudo
		Network.player_names[host_id] = Network.nickname

		# Display host in UI
		_add_player(host_id)
		_update_player_label(host_id, Network.nickname)

	###################################################
	# CLIENT INITIALIZATION
	###################################################
	else:
		start_button.visible = false



###################################################
# CLIENT CONNECTED
###################################################

func _on_connected():
	var mp = get_tree().get_multiplayer()
	var my_id = mp.get_unique_id()

	print("CLIENT: connected to server — sending nickname")

	_add_player(my_id)
	_update_player_label(my_id, Network.nickname)

	# send nickname to host (ID = 1)
	rpc_id(1, "register_name_request", Network.nickname)

	status_label.text = "Connected. Waiting for players..."


###################################################
# SERVER RECEIVES NAME FROM CLIENT
###################################################

@rpc("any_peer")
func register_name_request(name: String):
	var mp = get_tree().get_multiplayer()

	if mp.is_server():
		var sender_id = mp.get_remote_sender_id()
		Network.player_names[sender_id] = name

		print("SERVER REGISTER:", sender_id, name)

		# broadcast the client's name to all players
		rpc("register_name_broadcast", sender_id, name)

		# also send host name to the newly connected client
		var host_id = mp.get_unique_id()
		rpc_id(sender_id, "register_name_broadcast", host_id, Network.player_names[host_id])



###################################################
# RECEIVE A BROADCASTED NAME
###################################################

@rpc("any_peer")
func register_name_broadcast(peer_id: int, name: String):
	print("BROADCAST:", peer_id, name)

	Network.player_names[peer_id] = name

	_add_player(peer_id)
	_update_player_label(peer_id, name)



###################################################
# SIGNAL: PLAYER CONNECTED
###################################################

func _on_player_connected(peer_id):
	print("PLAYER CONNECTED:", peer_id)
	_add_player(peer_id) 



###################################################
# SIGNAL: PLAYER DISCONNECTED
###################################################

func _on_player_disconnected(peer_id):
	print("PLAYER DISCONNECTED:", peer_id)

	if players_list.has_node(str(peer_id)):
		players_list.get_node(str(peer_id)).queue_free()



###################################################
# UI FUNCTIONS — FINAL FIX
###################################################

func _add_player(peer_id):
	if !players_list.has_node(str(peer_id)):
		var label = Label.new()
		label.name = str(peer_id)
		label.text = "Loading..."
		players_list.add_child(label)

	# Update immediately with fallback
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
	
	# Attribuer les rôles avant de démarrer le jeu
	var player_ids = []
	player_ids.append(mp.get_unique_id())  # Host
	for peer_id in mp.get_peers():
		player_ids.append(peer_id)
	
	var result = RoleManager.assign_roles(player_ids)
	if not result.success:
		status_label.text = result.message
		return
	
	print("LOBBY: Rôles attribués - %d loups, %d villageois" % [result.num_wolves, result.num_villagers])
	
	# Envoyer les rôles à tous les joueurs
	for peer_id in player_ids:
		var role = RoleManager.get_player_role(peer_id)
		if role:
			rpc_id(peer_id, "receive_role", role.role_name, role.description, role.team)
	
	rpc("start_game_remote")
	_start_game()


@rpc("any_peer", "reliable")
func receive_role(role_name: String, description: String, team: String):
	print("CLIENT: Received role - %s (team: %s)" % [role_name, team])
	# Stocker temporairement le rôle dans Network pour le récupérer dans la scène de jeu
	Network.my_role_name = role_name
	Network.my_role_description = description
	Network.my_role_team = team


@rpc("any_peer", "reliable")
func start_game_remote():
	_start_game()


func _start_game():
	get_tree().change_scene_to_file("res://scenes/gameplay/test_scene.tscn")



###################################################
# CONNECTION FAILED
###################################################

func _on_failed():
	status_label.text = "Connection failed"
