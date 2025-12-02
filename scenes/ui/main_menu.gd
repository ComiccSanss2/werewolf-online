extends Control

const PORT := 9000

###################################################
#                   HOST
###################################################

func _on_HostButton_pressed():
	print("HOST: creating server")

	var name : String = $NicknameLineEdit.text.strip_edges()
	if name == "":
		name = "Player"
	Network.nickname = name

	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT) != OK:
		print("ERROR: cannot create server")
		return

	get_tree().get_multiplayer().multiplayer_peer = peer
	print("HOST OK")

	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


###################################################
#                   CLIENT
###################################################

func _on_JoinButton_pressed():
	print("CLIENT: joining")

	var name : String = $NicknameLineEdit.text.strip_edges()
	if name == "":
		name = "Player"
	Network.nickname = name

	var ip : String = $IpLineEdit.text.strip_edges()
	if ip == "":
		print("ERROR: no IP entered")
		return

	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		print("ERROR: cannot connect to server")
		return

	get_tree().get_multiplayer().multiplayer_peer = peer
	print("CLIENT OK")

	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
