extends Node

var nickname: String = "Player"
var is_host: bool = false
var players: Dictionary = {} 

signal lobby_players_updated(players)
signal game_started
signal connection_failed_ui

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 8



func host(port: int = DEFAULT_PORT) -> void:
	is_host = true
	players = {}
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		print("HOSTING FAILED: ", error)
		return
		
	multiplayer.multiplayer_peer = peer
	
	_add_player(multiplayer.get_unique_id(), nickname)
	_setup_signals()

func join(ip: String, port: int = DEFAULT_PORT) -> void:
	is_host = false
	players = {}
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	
	if error != OK:
		print("JOIN FAILED: ", error)
		return

	multiplayer.multiplayer_peer = peer
	_setup_signals()

func _setup_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func(): connection_failed_ui.emit())
	
# --- 2. Gestione della Lobby e Sincronizzazione ---

func _add_player(id: int, name: String) -> void:
	players[id] = {"name": name}
	if is_host:
		rpc("_sync_lobby_data", players)

@rpc("any_peer", "call_local", "reliable")
func _sync_lobby_data(synced_players: Dictionary) -> void:
	players = synced_players
	lobby_players_updated.emit(players)

@rpc("reliable")
func request_nickname() -> void:
	rpc_id(1, "receive_nickname", nickname)

@rpc("reliable", "any_peer")
func receive_nickname(name: String) -> void:
	var new_id = multiplayer.get_remote_sender_id()
	_add_player(new_id, name)


func _on_peer_connected(id: int) -> void:
	if is_host:
		rpc_id(id, "request_nickname")

func _on_peer_disconnected(id: int) -> void:
	if is_host:
		players.erase(id)
		rpc("_sync_lobby_data", players)


func start_game():
	if is_host:
		rpc("rpc_start_game")

@rpc("any_peer", "call_local", "reliable")
func rpc_start_game():
	game_started.emit()



@rpc("any_peer", "call_local", "reliable")
func request_player_hide_state(new_state: bool, chest_position: Vector2 = Vector2.ZERO): 
	if not get_tree().get_multiplayer().is_server(): return

	var requester_id: int = multiplayer.get_remote_sender_id()
	if requester_id == 0:
		requester_id = multiplayer.get_unique_id()
	
	var chest_manager = get_tree().get_root().get_node_or_null("TestScene/TileMap_Interactions")
	if not chest_manager:
		push_error("TileMap_Interactions non trovato.")
		return

	if new_state: 
		
		# 1. Vérifie si le coffre est libre
		if chest_manager.is_chest_free(chest_position):
			
			# 2. Marque le coffre comme occupée et synchronise l'état du joueur
			chest_manager.set_chest_occupant(chest_position, requester_id)
			_find_and_sync_player_state(requester_id, new_state)
	
	else: # Demande de Révélation (Unhiding)
		
		chest_manager.clear_chest_occupant(requester_id) 
		_find_and_sync_player_state(requester_id, new_state)


func _find_and_sync_player_state(player_id: int, new_state: bool):
	
	var player_node_path = "TestScene/Players/Player_" + str(player_id) 
	
	var root = get_tree().get_root()
	
	var player_node = root.get_node_or_null(player_node_path) 

	if player_node:
		player_node.rpc("sync_player_visual_state", new_state)
	else:
		push_error("ERROR, Node Player not found " + str(player_id) + " On Path: " + player_node_path)




@rpc("any_peer", "call_local", "reliable")
func request_chest_occupancy_state(chest_position: Vector2):
	if not get_tree().get_multiplayer().is_server(): return

	var requester_id: int = multiplayer.get_remote_sender_id()
	if requester_id == 0:
		requester_id = multiplayer.get_unique_id()
	
	var chest_manager = get_tree().get_root().get_node_or_null("TestScene/TileMap_Interactions")
	if not chest_manager: return

	var is_occupied = !chest_manager.is_chest_free(chest_position)
	
	# Le serveur répond directement au client demandeur
	rpc_id(requester_id, "receive_chest_occupancy_state", is_occupied)

@rpc("reliable", "call_local") 
func receive_chest_occupancy_state(is_occupied: bool):
	var player_id = multiplayer.get_unique_id()
	var player_node_path = "TestScene/Players/Player_" + str(player_id) 
	
	var root = get_tree().get_root()
	var player_node = root.get_node_or_null(player_node_path) 
	
	if player_node:
		player_node.update_chest_ui(is_occupied)
