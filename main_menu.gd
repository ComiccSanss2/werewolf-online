extends Control

const PORT := 9000

func _on_HostButton_pressed():
	print("HOST: creating server")
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(PORT)

	get_tree().get_multiplayer().multiplayer_peer = peer
	print("HOST OK")

	get_tree().change_scene_to_file("res://test_scene.tscn")


func _on_JoinButton_pressed():
	print("CLIENT: joining")

	var ip:String = $IpLineEdit.text  
	var peer := ENetMultiplayerPeer.new()
	peer.create_client(ip, PORT)

	get_tree().get_multiplayer().multiplayer_peer = peer
	print("CLIENT OK")

	get_tree().change_scene_to_file("res://test_scene.tscn")
