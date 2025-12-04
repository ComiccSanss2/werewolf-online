extends Node

var nickname: String = "Player"
var is_host: bool = false
var players: Dictionary = {} 

signal lobby_players_updated(players)
signal game_started
signal connection_failed_ui
signal game_over(winning_team) 

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 8
const ROLE_VILLAGEOIS: String = "villageois"
const ROLE_WEREWOLF: String = "werewolf"
const PLAYER_COLORS = [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.ORANGE, Color.PURPLE, Color.CYAN, Color.MAGENTA, Color(1.0, 0.5, 0.0), Color(0.5, 0.0, 0.5)]

func host(port: int = DEFAULT_PORT) -> void:
	is_host = true
	players = {}
	var peer = ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK: return
	multiplayer.multiplayer_peer = peer
	_add_player(multiplayer.get_unique_id(), nickname)
	_setup_signals()

func join(ip: String, port: int = DEFAULT_PORT) -> void:
	is_host = false
	players = {}
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK: return
	multiplayer.multiplayer_peer = peer
	_setup_signals()

func _setup_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connection_failed.is_connected(func(): connection_failed_ui.emit()):
		multiplayer.connection_failed.connect(func(): connection_failed_ui.emit())

func _add_player(id: int, name: String) -> void:
	players[id] = {"name": name}
	if not players[id].has("color"): players[id]["color"] = _get_available_color()
	if is_host: rpc("_sync_lobby_data", players)

func _get_available_color() -> Color:
	var used = []
	for pid in players:
		if players[pid].has("color"): used.append(players[pid]["color"])
	for c in PLAYER_COLORS:
		if not c in used: return c
	return PLAYER_COLORS.pick_random()

@rpc("any_peer", "call_local", "reliable")
func _sync_lobby_data(synced_players: Dictionary) -> void:
	players = synced_players
	lobby_players_updated.emit(players)

@rpc("reliable")
func request_nickname() -> void: rpc_id(1, "receive_nickname", nickname)

@rpc("reliable", "any_peer")
func receive_nickname(name: String) -> void: _add_player(multiplayer.get_remote_sender_id(), name)

func _on_peer_connected(id: int) -> void:
	if is_host: rpc_id(id, "request_nickname")

func _on_peer_disconnected(id: int) -> void:
	if is_host:
		players.erase(id)
		rpc("_sync_lobby_data", players)

func _assign_roles() -> void:
	if not is_host: return
	var ids = players.keys()
	if ids.size() < 2: return
	var num_wolves = max(1, ids.size() / 4)
	if ids.size() <= 4: num_wolves = 1
	elif ids.size() <= 8: num_wolves = 2
	var shuffled = ids.duplicate()
	shuffled.shuffle()
	for i in range(shuffled.size()):
		var pid = shuffled[i]
		players[pid]["role"] = ROLE_WEREWOLF if i < num_wolves else ROLE_VILLAGEOIS
	rpc("_sync_lobby_data", players)

func start_game():
	if is_host:
		_assign_roles()
		rpc("rpc_start_game")

@rpc("any_peer", "call_local", "reliable")
func rpc_start_game():
	game_started.emit()

# --- HELPER SECURISE POUR TROUVER LA SCENE ---
func get_game_scene() -> Node:
	return get_tree().get_root().get_node_or_null("TestScene")

# --- GESTION COFFRES ---
@rpc("any_peer", "call_local", "reliable")
func request_player_hide_state(new_state: bool, chest_pos: Vector2 = Vector2.ZERO): 
	if not multiplayer.is_server(): return
	var req_id = multiplayer.get_remote_sender_id()
	if req_id == 0: req_id = multiplayer.get_unique_id()
	
	var scene = get_game_scene()
	if not scene: return
	
	var chest_mgr = scene.get_node_or_null("TileMap_Interactions")
	if not chest_mgr: return

	if new_state: 
		if chest_mgr.is_chest_free(chest_pos):
			chest_mgr.set_chest_occupant(chest_pos, req_id)
			_sync_player_node_state(req_id, new_state)
	else:
		chest_mgr.clear_chest_occupant(req_id) 
		_sync_player_node_state(req_id, new_state)

func _sync_player_node_state(pid: int, state: bool):
	var scene = get_game_scene()
	if not scene: return
	var p = scene.get_node_or_null("Players/Player_" + str(pid))
	if p: p.rpc("sync_player_visual_state", state)

@rpc("any_peer", "call_local", "reliable")
func request_chest_occupancy_state(chest_pos: Vector2):
	if not multiplayer.is_server(): return
	var req_id = multiplayer.get_remote_sender_id()
	if req_id == 0: req_id = multiplayer.get_unique_id()
	
	var scene = get_game_scene()
	if not scene: return
	var chest_mgr = scene.get_node_or_null("TileMap_Interactions")
	if chest_mgr:
		rpc_id(req_id, "receive_chest_occupancy_state", !chest_mgr.is_chest_free(chest_pos))

@rpc("reliable", "call_local") 
func receive_chest_occupancy_state(is_occupied: bool):
	var scene = get_game_scene()
	if not scene: return
	var p = scene.get_node_or_null("Players/Player_" + str(multiplayer.get_unique_id()))
	if p: p.update_chest_ui(is_occupied)

# --- HELPERS ---
func is_werewolf(id: int) -> bool: return players.has(id) and players[id].get("role") == ROLE_WEREWOLF
func is_player_dead(id: int) -> bool: return players.has(id) and players[id].get("is_dead", false)
func get_alive_players() -> Array:
	var a = []
	for id in players:
		if not is_player_dead(id): a.append(id)
	return a

# --- MORT ET VICTOIRE ---

@rpc("any_peer", "call_local", "reliable")
func request_kill_player(target_id: int) -> void:
	if not multiplayer.is_server(): return
	if not players.has(target_id) or is_player_dead(target_id): return
	
	var scene = get_game_scene()
	if not scene: return
	
	var victim_node = scene.get_node_or_null("Players/Player_" + str(target_id))
	var pos = Vector2.ZERO
	var col = Color.WHITE
	var is_flipped = false
	
	if victim_node:
		pos = victim_node.global_position
		col = victim_node.anim.modulate
		is_flipped = victim_node.anim.flip_h
		victim_node.rpc("play_death_animation")

	players[target_id]["is_dead"] = true
	rpc("_sync_lobby_data", players)
	
	# Spawn du cadavre
	scene.rpc("spawn_corpse_on_all", pos, col, is_flipped)
	
	check_win_condition()

func check_win_condition():
	var wolves = 0
	var villagers = 0
	for id in players:
		if not is_player_dead(id):
			if players[id]["role"] == ROLE_WEREWOLF: wolves += 1
			else: villagers += 1
	print("WIN CHECK: Loups=%d, Villageois=%d" % [wolves, villagers])
	if wolves == 0: rpc("rpc_game_over", "VILLAGEOIS")
	elif wolves >= villagers: rpc("rpc_game_over", "LOUPS-GAROUS")

@rpc("call_local", "reliable")
func rpc_game_over(winner: String):
	print("VICTOIRE : ", winner)
	game_over.emit(winner)

@rpc("any_peer", "call_local", "reliable")
func kill_player_in_scene(pid: int) -> void: pass

func stop_network():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
