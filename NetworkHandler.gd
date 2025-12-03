extends Node

# Dati della Lobby
var nickname: String = "Player"
var is_host: bool = false
var players: Dictionary = {} # {peer_id: {name: "Nome", ...}}

# Segnali per le Scene (Lobby/Menu)
signal lobby_players_updated(players)
signal game_started
signal connection_failed_ui

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 8


# --- 1. Inizializzazione Rete ---

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

func _on_peer_connected(id: int) -> void:
	if is_host:
		rpc_id(id, "request_nickname")

@rpc("reliable")
func request_nickname() -> void:
	rpc_id(1, "receive_nickname", nickname)

@rpc("reliable", "any_peer")
func receive_nickname(name: String) -> void:
	var new_id = multiplayer.get_remote_sender_id()
	_add_player(new_id, name)


func _on_peer_disconnected(id: int) -> void:
	if is_host:
		players.erase(id)
		rpc("_sync_lobby_data", players)

# --- 3. Avvio Partita ---

func start_game():
	if is_host:
		rpc("rpc_start_game")

@rpc("any_peer", "call_local", "reliable")
func rpc_start_game():
	game_started.emit()


# ----------------------------------------------------------------------
# --- 4. GESTIONE CENTRALIZZATA STATO NASCOSTO ---
# ----------------------------------------------------------------------

@rpc("any_peer", "call_local")
func request_player_hide_state(new_state: bool):
	# Eseguito SOLO sull'Host (ID 1)
	if not get_tree().get_multiplayer().is_server(): return

	var requester_id: int
	
	if multiplayer.get_remote_sender_id() == 0:
		requester_id = multiplayer.get_unique_id()
	else:
		requester_id = multiplayer.get_remote_sender_id()
	
	_find_and_sync_player_state(requester_id, new_state)


func _find_and_sync_player_state(player_id: int, new_state: bool):
	
	# Percorso corretto (coerente con test_scene.gd)
	var player_node_path = "TestScene/Players/Player_" + str(player_id) 
	
	var root = get_tree().get_root()
	
	var player_node = root.get_node_or_null(player_node_path) 

	if player_node:
		# Il Server ordina al nodo Player corretto di eseguire l'RPC di sincronizzazione
		player_node.rpc("sync_player_visual_state", new_state)
	else:
		push_error("ERRORE CRITICO: Nodo Player non trovato per l'ID: " + str(player_id) + " al percorso: " + player_node_path)
