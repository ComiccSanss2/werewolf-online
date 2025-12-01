extends Node2D

@onready var spawn_point = $SpawnPoint
var PlayerScene = preload("res://player.tscn")

func _ready():
	var mp = get_tree().get_multiplayer()

	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)

	# Spawn du joueur local
	spawn_player(mp.get_unique_id())

func _on_player_connected(peer_id):
	spawn_player(peer_id)

func _on_player_disconnected(peer_id):
	# Supprime le joueur qui s'est déconnecté
	if has_node(str(peer_id)):
		get_node(str(peer_id)).queue_free()

func spawn_player(peer_id):
	var p = PlayerScene.instantiate()
	p.name = str(peer_id)
	add_child(p)

	p.global_position = spawn_point.global_position
	p.set_multiplayer_authority(peer_id)
