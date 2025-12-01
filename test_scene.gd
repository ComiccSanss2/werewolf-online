extends Node2D

@onready var spawn_point = $SpawnPoint
var PlayerScene = preload("res://player.tscn")

func _ready():
	var mp = get_tree().get_multiplayer()
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)

	# Spawn LOCAL seulement
	spawn_player(mp.get_unique_id())

func _on_player_connected(peer_id):
	var mp = get_tree().get_multiplayer()
	var local_id = mp.get_unique_id()

	# VERY IMPORTANT !!!
	if peer_id == local_id:
		print("IGNORED self connect:", peer_id)
		return

	# Avoid double spawn
	if has_node(str(peer_id)):
		print("Player already exists:", peer_id)
		return

	print("CONNECTED:", peer_id)
	spawn_player(peer_id)

func _on_player_disconnected(peer_id):
	print("DISCONNECTED:", peer_id)
	if has_node(str(peer_id)):
		get_node(str(peer_id)).queue_free()

func spawn_player(peer_id):
	print("SPAWN PLAYER:", peer_id)
	var p = PlayerScene.instantiate()
	p.name = str(peer_id)

	p.set_multiplayer_authority(peer_id)

	add_child(p)
	var spawns = $SpawnPoints.get_children()
	var spawn = spawns[randi() % spawns.size()]
	p.global_position = spawn.global_position


	print("SET AUTHORITY:", peer_id)
