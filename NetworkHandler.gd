extends Node

# Gestionnaire central du réseau et de l'état du jeu

# Variables globales
var nickname = "Player"
var is_host = false
var players = {}  
var is_gameplay_active: bool = false
var public_ip_address = "" 

# Thread pour l'UPnP
var upnp_thread: Thread = null

# --- SYSTEME DE QUETES ---
const GOAL_ROCKS = 6
const GOAL_WATER = 6
var players_tasks_progress = {}

# Signaux
signal lobby_players_updated(players)
signal game_started
signal connection_failed_ui
signal game_over(winning_team)
signal upnp_completed(ip_address) 

const DEFAULT_PORT = 8910
const MAX_PLAYERS = 15
const ROLE_VILLAGER = "Villager"
const ROLE_WEREWOLF = "Werewolf"
const ROLE_WITCH = "Witch"

const PLAYER_COLORS = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.ORANGE,
	Color.PURPLE, Color.CYAN, Color.MAGENTA, Color.PINK, Color.LIME_GREEN,
	Color(1.0, 0.5, 0.0), Color(0.5, 0.0, 0.5), Color(0.0, 0.5, 0.5),
	Color(1.0, 0.75, 0.8), Color(0.5, 1.0, 0.5), Color(0.75, 0.5, 1.0)
]

func _ready():
	# On s'assure que le thread est propre à la sortie
	process_mode = Node.PROCESS_MODE_ALWAYS

func _exit_tree():
	if upnp_thread and upnp_thread.is_started():
		upnp_thread.wait_to_finish()

# --- UPnP SETUP (THREADÉ) ---

func _start_upnp_thread():
	upnp_thread = Thread.new()
	# On lance la fonction _upnp_task dans un fil séparé
	upnp_thread.start(_upnp_task)

func _upnp_task():
	print("UPnP: Démarrage de la découverte...")
	var upnp = UPNP.new()
	
	# 1. Découverte (Peut prendre 2-3 secondes)
	var discover_result = upnp.discover()
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPnP: Échec Découverte (Code %s)" % discover_result)
		call_deferred("_fallback_get_ip") # Plan B
		return

	# 2. Gateway
	if not upnp.get_gateway() or not upnp.get_gateway().is_valid_gateway():
		print("UPnP: Gateway Invalide")
		call_deferred("_fallback_get_ip") # Plan B
		return

	# 3. Mapping
	print("UPnP: Tentative de mapping du port %d..." % DEFAULT_PORT)
	var map_result = upnp.add_port_mapping(DEFAULT_PORT, DEFAULT_PORT, "LoupGarou_UDP", "UDP")
	
	if map_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPnP: Échec Mapping Port (Code %s)" % map_result)
		# On essaie quand même de chopper l'IP même si le port a foiré
		call_deferred("_fallback_get_ip") 
	else:
		public_ip_address = upnp.query_external_address()
		print("UPnP: Succès ! IP Trouvée : %s" % public_ip_address)
		# Important : call_deferred pour revenir au thread principal pour l'UI
		call_deferred("emit_signal", "upnp_completed", public_ip_address)

# PLAN B : Si l'UPnP échoue à trouver l'IP, on demande à Internet
func _fallback_get_ip():
	print("UPnP échoué ou partiel. Tentative de récupération IP via HTTP...")
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_ip_request_completed)
	http.request("https://api.ipify.org")

func _on_ip_request_completed(result, response_code, headers, body):
	if response_code == 200:
		public_ip_address = body.get_string_from_utf8()
		print("HTTP IP Succès : ", public_ip_address)
		upnp_completed.emit(public_ip_address + " (Port ?)") 
	else:
		print("Échec total récupération IP.")
		upnp_completed.emit("Erreur : Impossible de trouver l'IP")
	
	# Nettoyage du noeud HTTP temporaire
	var http = get_children().back()
	if http is HTTPRequest: http.queue_free()

# ========== Connexion réseau ==========

func host(port: int = DEFAULT_PORT) -> void:
	is_host = true
	players = {}
	
	# On lance l'UPnP en tâche de fond
	_start_upnp_thread()
	
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

# ... (LE RESTE DU CODE EST IDENTIQUE, COPIE LA SUITE DE TON ANCIEN FICHIER ICI) ...
# (Gestion des joueurs, Quêtes, Coffres, etc.)

func _add_player(id: int, player_name: String) -> void:
	players[id] = {"name": player_name, "color": _get_available_color()}
	if is_host: rpc("_sync_lobby_data", players)

func _get_available_color() -> Color:
	var used_colors = []
	for p in players.values():
		if p.has("color"): used_colors.append(p["color"])
	for color in PLAYER_COLORS:
		if not color in used_colors: return color
	return PLAYER_COLORS.pick_random()

func _get_sender_id() -> int:
	var id = multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()

func _get_player_node(player_id: int):
	return get_tree().get_root().get_node_or_null("TestScene/Players/Player_%d" % player_id)

func _get_chest_manager():
	return get_tree().get_root().get_node_or_null("TestScene/TileMap_Interactions")

func get_game_scene() -> Node:
	return get_tree().get_root().get_node_or_null("TestScene")

@rpc("any_peer", "call_local", "reliable")
func _sync_lobby_data(synced_players: Dictionary) -> void:
	players = synced_players
	lobby_players_updated.emit(players)

@rpc("reliable")
func request_nickname() -> void: rpc_id(1, "receive_nickname", nickname)

@rpc("reliable", "any_peer")
func receive_nickname(player_name: String) -> void:
	_add_player(multiplayer.get_remote_sender_id(), player_name)

func _on_peer_connected(id: int) -> void:
	if is_host: rpc_id(id, "request_nickname")

func _on_peer_disconnected(id: int) -> void:
	if is_host:
		players.erase(id)
		if players_tasks_progress.has(id): players_tasks_progress.erase(id)
		rpc("_sync_lobby_data", players)
		rpc("sync_tasks_data", players_tasks_progress)

func _assign_roles() -> void:
	if not is_host: return
	var ids = players.keys()
	var n = ids.size()
	if n < 2: return
	var num_wolves = 1
	if n > 8: num_wolves = 2
	
	var shuffled = ids.duplicate()
	shuffled.shuffle()
	for i in range(shuffled.size()):
		var pid = shuffled[i]
		if i < num_wolves:
			players[pid]["role"] = ROLE_WEREWOLF
			players[pid]["has_killed"] = false
		elif i == num_wolves and n >= 3:
			players[pid]["role"] = ROLE_WITCH
			players[pid]["has_revived"] = false
		else:
			players[pid]["role"] = ROLE_VILLAGER
	
	rpc("_sync_lobby_data", players)
	init_tasks_for_game()

func start_game():
	if is_host:
		_assign_roles()
		rpc("rpc_start_game")

@rpc("any_peer", "call_local", "reliable")
func rpc_start_game():
	game_started.emit()

func reset_night_actions():
	if not multiplayer.is_server(): return
	for pid in players:
		if is_werewolf(pid): players[pid]["has_killed"] = false
	rpc("_sync_lobby_data", players)

func init_tasks_for_game():
	players_tasks_progress.clear()
	for id in players:
		if players[id]["role"] != ROLE_WEREWOLF:
			players_tasks_progress[id] = { "rocks": 0, "water": 0, "finished": false }
	rpc("sync_tasks_data", players_tasks_progress)

@rpc("call_local", "reliable")
func sync_tasks_data(data: Dictionary):
	players_tasks_progress = data

@rpc("any_peer", "call_local", "reliable")
func report_task_completed(type: String):
	if not multiplayer.is_server(): return
	var pid = _get_sender_id()
	if not players_tasks_progress.has(pid): return
	var prog = players_tasks_progress[pid]
	if type == "rock" and prog["rocks"] < GOAL_ROCKS: prog["rocks"] += 1
	elif type == "water" and prog["water"] < GOAL_WATER: prog["water"] += 1
	if prog["rocks"] >= GOAL_ROCKS and prog["water"] >= GOAL_WATER: prog["finished"] = true
	rpc("sync_tasks_data", players_tasks_progress)
	check_task_win_condition()

func check_task_win_condition():
	var all_finished = true
	var villager_count = 0
	for pid in players_tasks_progress:
		if not is_player_dead(pid): 
			villager_count += 1
			if not players_tasks_progress[pid]["finished"]:
				all_finished = false
				break
	if villager_count > 0 and all_finished:
		rpc("rpc_game_over", "VILLAGERS (TASKS)")

@rpc("any_peer", "call_local", "reliable")
func request_player_hide_state(new_state: bool, chest_pos: Vector2 = Vector2.ZERO):
	if not multiplayer.is_server(): return
	var requester_id = _get_sender_id()
	var chest_mgr = _get_chest_manager()
	if not chest_mgr: return
	if new_state:
		if chest_mgr.is_chest_free(chest_pos):
			chest_mgr.set_chest_occupant(chest_pos, requester_id)
			_sync_player_visual(requester_id, new_state)
	else:
		chest_mgr.clear_chest_occupant(requester_id)
		_sync_player_visual(requester_id, new_state)

func _sync_player_visual(player_id: int, new_state: bool):
	var player = _get_player_node(player_id)
	if player: player.rpc("sync_player_visual_state", new_state)

@rpc("any_peer", "call_local", "reliable")
func request_chest_occupancy_state(chest_pos: Vector2):
	if not multiplayer.is_server(): return
	var chest_mgr = _get_chest_manager()
	if chest_mgr:
		rpc_id(_get_sender_id(), "receive_chest_occupancy_state", !chest_mgr.is_chest_free(chest_pos))

@rpc("reliable", "call_local")
func receive_chest_occupancy_state(is_occupied: bool):
	var player = _get_player_node(multiplayer.get_unique_id())
	if player: player.update_chest_ui(is_occupied)

func get_player_role(id: int) -> String: return players.get(id, {}).get("role", ROLE_VILLAGER)
func is_werewolf(id: int) -> bool: return get_player_role(id) == ROLE_WEREWOLF
func is_sorciere(id: int) -> bool: return get_player_role(id) == ROLE_WITCH
func is_player_dead(id: int) -> bool: return players.get(id, {}).get("is_dead", false)
func get_alive_players() -> Array: return players.keys().filter(func(id): return not is_player_dead(id))
func get_dead_players() -> Array: return players.keys().filter(func(id): return is_player_dead(id))

@rpc("any_peer", "call_local", "reliable")
func request_kill_player(target_id: int) -> void:
	if not multiplayer.is_server(): return
	var killer_id = _get_sender_id()
	if not players.has(killer_id) or not players.has(target_id): return
	if not is_werewolf(killer_id) or is_player_dead(killer_id): return
	if is_player_dead(target_id): return
	if players[killer_id].get("has_killed", false): return
	
	var scene = get_game_scene()
	if not scene: return
	var victim_node = scene.get_node_or_null("Players/Player_%d" % target_id)
	var pos = Vector2.ZERO
	var col = Color.WHITE
	var is_flipped = false
	if victim_node:
		pos = victim_node.global_position
		col = victim_node.anim.modulate
		is_flipped = victim_node.anim.flip_h
		victim_node.rpc("play_death_animation")
	
	players[target_id]["is_dead"] = true
	players[killer_id]["has_killed"] = true
	rpc("_sync_lobby_data", players)
	scene.rpc("spawn_corpse_on_all", target_id, pos, col, is_flipped)
	check_win_condition()

func eliminate_player_by_vote(target_id: int) -> void:
	if not multiplayer.is_server(): return
	var scene = get_game_scene()
	if not scene: return
	var victim_node = scene.get_node_or_null("Players/Player_%d" % target_id)
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
	scene.rpc("spawn_corpse_on_all", target_id, pos, col, is_flipped)
	check_win_condition()

@rpc("any_peer", "call_local", "reliable")
func request_revive_player(target_id: int) -> void:
	if not multiplayer.is_server(): return
	var sorciere_id = _get_sender_id()
	if not is_sorciere(sorciere_id) or is_player_dead(target_id): return
	if players[sorciere_id].get("has_revived", false): return
	players[target_id]["is_dead"] = false
	players[sorciere_id]["has_revived"] = true
	rpc("_sync_lobby_data", players)
	var scene = get_game_scene()
	if scene:
		var corpse = scene.get_node_or_null("DeadBodies/Corpse_%d" % target_id)
		var revive_pos = corpse.global_position if corpse else Vector2.ZERO
		rpc("revive_player_in_scene", target_id)
		scene.rpc("remove_corpse_on_all", target_id, revive_pos)

@rpc("any_peer", "call_local", "reliable")
func revive_player_in_scene(player_id: int) -> void:
	var player = _get_player_node(player_id)
	if player: player.rpc("revive_character")

@rpc("any_peer", "call_local", "reliable")
func request_area_stun(center_pos: Vector2, radius: float, duration: float, ignore_player_id: int):
	if not multiplayer.is_server(): return
	var scene = get_game_scene()
	if not scene: return
	var players_node = scene.get_node_or_null("Players")
	if not players_node: return
	for player in players_node.get_children():
		var pid = player.get_multiplayer_authority()
		if pid == ignore_player_id or is_player_dead(pid): continue
		if player.global_position.distance_to(center_pos) <= radius:
			rpc("apply_stun_to_player", pid, duration)

@rpc("call_local", "reliable")
func apply_stun_to_player(target_id: int, duration: float):
	var player = _get_player_node(target_id)
	if player: player.receive_stun(duration)

func check_win_condition():
	var wolves = 0
	var villagers = 0
	for id in players:
		if not is_player_dead(id):
			if players[id].get("role") == ROLE_WEREWOLF: wolves += 1
			else: villagers += 1
	if wolves == 0: rpc("rpc_game_over", "VILLAGERS")
	elif wolves >= villagers: rpc("rpc_game_over", "WEREWOLF")

@rpc("call_local", "reliable")
func rpc_game_over(winner: String): game_over.emit(winner)

func stop_network():
	if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
