extends Node2D

var PlayerScene := preload("res://player.tscn")

@onready var players_root: Node = $Players
@onready var spawn_points = $SpawnPoints.get_children()


func _ready() -> void:
	var mp := get_tree().get_multiplayer()

	# Network signals
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)

	if mp.is_server():
		# Spawn host (ID 1)
		_spawn_for_peer(mp.get_unique_id())
		
		# Spawna every connected client
		for peer_id in mp.get_peers():
			_spawn_for_peer(peer_id)


func _on_player_connected(peer_id: int) -> void:
	if get_tree().get_multiplayer().is_server():
		_spawn_for_peer(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	rpc("despawn_player_on_all", peer_id)


func _spawn_for_peer(peer_id: int) -> void:
	rpc("spawn_player_on_all", peer_id)


# --- RPC: Player Creation ---
@rpc("reliable", "call_local")
func spawn_player_on_all(peer_id: int):
	
	var player_name = "Player_" + str(peer_id) 
	
	if players_root.has_node(player_name):
		return
	
	var p = PlayerScene.instantiate()
	p.name = player_name 
	
	p.set_multiplayer_authority(peer_id)

	# Assign random spawnpoint
	var sp_index = randi() % spawn_points.size()
	var sp = spawn_points[sp_index]
	p.global_position = sp.global_position

	players_root.add_child(p)


# --- RPC: Kill PLayer (despawn) ---
@rpc("reliable", "call_local")
func despawn_player_on_all(peer_id: int):
	var player_name = "Player_" + str(peer_id) 
	var p := players_root.get_node_or_null(player_name)
	if p:
		p.queue_free()
