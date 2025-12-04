extends Node

# Gestionnaire central du réseau et de l'état du jeu

# Variables globales
var nickname = "Player"
var is_host = false
var players = {}  # { id: { name, color, role, is_dead, has_revived } }

# Signaux pour communiquer avec l'UI
signal lobby_players_updated(players)
signal game_started
signal connection_failed_ui
signal game_over(winning_team)

# Constantes réseau
const DEFAULT_PORT = 8910
const MAX_PLAYERS = 8

# Rôles disponibles
const ROLE_VILLAGEOIS = "villageois"
const ROLE_WEREWOLF = "werewolf"
const ROLE_SORCIERE = "sorciere"

# Palette de couleurs pour les joueurs
const PLAYER_COLORS = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.ORANGE,
	Color.PURPLE, Color.CYAN, Color.MAGENTA, Color.PINK, Color.LIME_GREEN,
	Color(1.0, 0.5, 0.0), Color(0.5, 0.0, 0.5), Color(0.0, 0.5, 0.5),
	Color(1.0, 0.75, 0.8), Color(0.5, 1.0, 0.5), Color(0.75, 0.5, 1.0)
]

# ========== Connexion réseau ==========

# Crée un serveur
func host(port: int = DEFAULT_PORT) -> void:
	is_host = true
	players = {}
	var peer = ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK: return
	multiplayer.multiplayer_peer = peer
	_add_player(multiplayer.get_unique_id(), nickname)
	_setup_signals()

# Rejoint un serveur
func join(ip: String, port: int = DEFAULT_PORT) -> void:
	is_host = false
	players = {}
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK: return
	multiplayer.multiplayer_peer = peer
	_setup_signals()

# Configure les signaux réseau
func _setup_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func(): connection_failed_ui.emit())

# ========== Gestion des joueurs ==========

# Ajoute un joueur au dictionnaire
func _add_player(id: int, player_name: String) -> void:
	players[id] = {"name": player_name, "color": _get_available_color()}
	if is_host: rpc("_sync_lobby_data", players)

# Retourne une couleur non utilisée
func _get_available_color() -> Color:
	var used_colors = []
	for p in players.values():
		if p.has("color"): used_colors.append(p["color"])
	for color in PLAYER_COLORS:
		if not color in used_colors: return color
	return PLAYER_COLORS.pick_random()

# ========== Helpers ==========

# Retourne l'ID de l'envoyeur RPC
func _get_sender_id() -> int:
	var id = multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()

# Retourne le nœud d'un joueur
func _get_player_node(player_id: int):
	return get_tree().get_root().get_node_or_null("TestScene/Players/Player_%d" % player_id)

# Retourne le gestionnaire de coffres
func _get_chest_manager():
	return get_tree().get_root().get_node_or_null("TestScene/TileMap_Interactions")

# Retourne la scène de jeu
func get_game_scene() -> Node:
	return get_tree().get_root().get_node_or_null("TestScene")

# ========== Synchronisation lobby ==========

# RPC: Synchronise les données du lobby
@rpc("any_peer", "call_local", "reliable")
func _sync_lobby_data(synced_players: Dictionary) -> void:
	players = synced_players
	lobby_players_updated.emit(players)

# RPC: Demande le pseudo d'un nouveau joueur
@rpc("reliable")
func request_nickname() -> void:
	rpc_id(1, "receive_nickname", nickname)

# RPC: Reçoit le pseudo d'un joueur
@rpc("reliable", "any_peer")
func receive_nickname(player_name: String) -> void:
	_add_player(multiplayer.get_remote_sender_id(), player_name)

# Signal: Joueur connecté
func _on_peer_connected(id: int) -> void:
	if is_host: rpc_id(id, "request_nickname")

# Signal: Joueur déconnecté
func _on_peer_disconnected(id: int) -> void:
	if is_host:
		players.erase(id)
		rpc("_sync_lobby_data", players)

# ========== Attribution des rôles ==========

# Assigne aléatoirement les rôles aux joueurs
func _assign_roles() -> void:
	if not is_host: return
	
	var player_ids = players.keys()
	var n = player_ids.size()
	if n < 2: return
	
	var num_werewolves = 1 if n <= 4 else 2
	var shuffled = player_ids.duplicate()
	shuffled.shuffle()
	
	for i in shuffled.size():
		var pid = shuffled[i]
		if i < num_werewolves:
			players[pid]["role"] = ROLE_WEREWOLF
			players[pid]["has_killed"] = false
		elif i == num_werewolves and n >= 3:
			players[pid]["role"] = ROLE_SORCIERE
			players[pid]["has_revived"] = false
		else:
			players[pid]["role"] = ROLE_VILLAGEOIS
	
	rpc("_sync_lobby_data", players)

# Démarre la partie
func start_game():
	if is_host:
		_assign_roles()
		rpc("rpc_start_game")

# RPC: Notifie tous les clients du démarrage
@rpc("any_peer", "call_local", "reliable")
func rpc_start_game():
	game_started.emit()

# Réinitialise les kills des loups-garous (début de nuit)
func reset_night_actions():
	if not multiplayer.is_server(): return
	for pid in players:
		if is_werewolf(pid):
			players[pid]["has_killed"] = false
	rpc("_sync_lobby_data", players)

# ========== Système de cachettes (coffres) ==========

# RPC: Demande de changer l'état de cachette d'un joueur
@rpc("any_peer", "call_local", "reliable")
func request_player_hide_state(new_state: bool, chest_position: Vector2 = Vector2.ZERO):
	if not multiplayer.is_server(): return
	
	var requester_id = _get_sender_id()
	var chest_manager = _get_chest_manager()
	if not chest_manager: return

	if new_state:
		if chest_manager.is_chest_free(chest_position):
			chest_manager.set_chest_occupant(chest_position, requester_id)
			_sync_player_visual(requester_id, new_state)
	else:
		chest_manager.clear_chest_occupant(requester_id)
		_sync_player_visual(requester_id, new_state)

# Synchronise l'état visuel (caché/visible) d'un joueur
func _sync_player_visual(player_id: int, new_state: bool):
	var player = _get_player_node(player_id)
	if player: player.rpc("sync_player_visual_state", new_state)

# RPC: Demande l'état d'occupation d'un coffre
@rpc("any_peer", "call_local", "reliable")
func request_chest_occupancy_state(chest_position: Vector2):
	if not multiplayer.is_server(): return
	
	var chest_manager = _get_chest_manager()
	if not chest_manager: return
	
	var is_occupied = not chest_manager.is_chest_free(chest_position)
	rpc_id(_get_sender_id(), "receive_chest_occupancy_state", is_occupied)

# RPC: Reçoit l'état d'occupation d'un coffre
@rpc("reliable", "call_local")
func receive_chest_occupancy_state(is_occupied: bool):
	var player = _get_player_node(multiplayer.get_unique_id())
	if player: player.update_chest_ui(is_occupied)

# ========== Requêtes d'état des joueurs ==========

# Retourne le rôle d'un joueur
func get_player_role(player_id: int) -> String:
	return players.get(player_id, {}).get("role", ROLE_VILLAGEOIS)

# Vérifie si un joueur est loup-garou
func is_werewolf(player_id: int) -> bool:
	return get_player_role(player_id) == ROLE_WEREWOLF

# Vérifie si un joueur est sorcière
func is_sorciere(player_id: int) -> bool:
	return get_player_role(player_id) == ROLE_SORCIERE

# Retourne la liste des loups-garous
func get_werewolves() -> Array:
	return players.keys().filter(func(id): return is_werewolf(id))

# Vérifie si un joueur est mort
func is_player_dead(player_id: int) -> bool:
	return players.get(player_id, {}).get("is_dead", false)

# Retourne la liste des joueurs vivants
func get_alive_players() -> Array:
	return players.keys().filter(func(id): return not is_player_dead(id))

# Retourne la liste des joueurs morts
func get_dead_players() -> Array:
	return players.keys().filter(func(id): return is_player_dead(id))

# ========== Actions kill/revive ==========

# RPC: Demande de tuer un joueur (chaque loup peut tuer individuellement)
@rpc("any_peer", "call_local", "reliable")
func request_kill_player(target_id: int) -> void:
	if not multiplayer.is_server(): return
	
	var killer_id = _get_sender_id()
	
	# Validations
	if not players.has(killer_id) or not players.has(target_id): return
	if not is_werewolf(killer_id) or is_player_dead(killer_id): return
	if is_player_dead(target_id): return
	
	# Vérifie que CE loup n'a pas déjà tué cette nuit
	if players[killer_id].get("has_killed", false): return
	
	var scene = get_game_scene()
	if not scene: return
	
	# Récupère les infos du joueur avant de le tuer
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
	
	# Spawn du cadavre
	scene.rpc("spawn_corpse_on_all", target_id, pos, col, is_flipped)
	
	check_win_condition()

# RPC: Tue un joueur dans la scène (legacy, utilisé par check_win)
@rpc("any_peer", "call_local", "reliable")
func kill_player_in_scene(player_id: int) -> void:
	var player = _get_player_node(player_id)
	if player: player.rpc("play_death_animation")

# Élimine un joueur par vote (sans vérification de rôle)
func eliminate_player_by_vote(target_id: int) -> void:
	if not multiplayer.is_server(): return
	if not players.has(target_id) or is_player_dead(target_id): return
	
	var scene = get_game_scene()
	if not scene: return
	
	# Récupère les infos du joueur
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

# RPC: Demande de ressusciter un joueur
@rpc("any_peer", "call_local", "reliable")
func request_revive_player(target_id: int) -> void:
	if not multiplayer.is_server(): return
	
	var sorciere_id = _get_sender_id()
	
	# Validations
	if not players.has(sorciere_id) or not players.has(target_id): return
	if not is_sorciere(sorciere_id): return
	if players[sorciere_id].get("has_revived", false): return
	if not is_player_dead(target_id): return

	players[target_id]["is_dead"] = false
	players[sorciere_id]["has_revived"] = true
	rpc("_sync_lobby_data", players)
	
	var scene = get_game_scene()
	if scene:
		scene.rpc("remove_corpse_on_all", target_id)
		rpc("revive_player_in_scene", target_id)

# RPC: Ressuscite un joueur dans la scène
@rpc("any_peer", "call_local", "reliable")
func revive_player_in_scene(player_id: int) -> void:
	var player = _get_player_node(player_id)
	if player: player.rpc("revive_character")

# ========== Système de victoire ==========

# Vérifie les conditions de victoire
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

# RPC: Notifie la fin de partie
@rpc("call_local", "reliable")
func rpc_game_over(winner: String):
	print("VICTOIRE : ", winner)
	game_over.emit(winner)

# ========== Nettoyage réseau ==========

# Arrête le réseau et nettoie
func stop_network():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
