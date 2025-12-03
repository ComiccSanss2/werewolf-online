extends Node2D

var PlayerScene := preload("res://player.tscn")

@onready var players_root: Node = $Players
@onready var spawn_points = $SpawnPoints.get_children()


func _ready() -> void:
	var mp := get_tree().get_multiplayer()

	# Segnali di rete:
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)

	# L'HOST spawna sé stesso e tutti i Client già connessi
	if mp.is_server():
		# Spawna l'Host (ID 1)
		_spawn_for_peer(mp.get_unique_id())
		
		# Spawna tutti i Client già connessi
		for peer_id in mp.get_peers():
			_spawn_for_peer(peer_id)


# Chiamato quando un nuovo giocatore si connette (solo sull'Host)
func _on_player_connected(peer_id: int) -> void:
	if get_tree().get_multiplayer().is_server():
		_spawn_for_peer(peer_id)


# Chiamato quando un giocatore si disconnette (solo sull'Host)
func _on_player_disconnected(peer_id: int) -> void:
	rpc("despawn_player_on_all", peer_id)


# Funzione Helper: L'Host chiama un RPC che istruisce tutti i peer
func _spawn_for_peer(peer_id: int) -> void:
	rpc("spawn_player_on_all", peer_id)


# --- RPC: CREAZIONE GIOCATORE ---
@rpc("reliable", "call_local")
func spawn_player_on_all(peer_id: int):
	
	var player_name = "Player_" + str(peer_id) # Naming corretto
	
	# Prevenire lo spawning se per qualche motivo il nodo è già presente
	if players_root.has_node(player_name):
		return
	
	var p = PlayerScene.instantiate()
	p.name = player_name # Rinomina l'istanza con il nome completo
	
	p.set_multiplayer_authority(peer_id)

	# Assegna uno Spawnpoint random
	var sp_index = randi() % spawn_points.size()
	var sp = spawn_points[sp_index]
	p.global_position = sp.global_position

	players_root.add_child(p)


# --- RPC: ELIMINAZIONE GIOCATORE ---
@rpc("reliable", "call_local")
func despawn_player_on_all(peer_id: int):
	var player_name = "Player_" + str(peer_id) # Usa il nome completo
	var p := players_root.get_node_or_null(player_name)
	if p:
		p.queue_free()
