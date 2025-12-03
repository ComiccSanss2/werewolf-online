extends Node

var nickname: String = "Player"
var is_host: bool = false
var players: Dictionary = {} 

signal lobby_players_updated(players)
signal game_started
signal connection_failed_ui

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 8

const ROLE_VILLAGEOIS: String = "villageois"
const ROLE_WEREWOLF: String = "werewolf"

# Palette de couleurs disponibles
const PLAYER_COLORS = [
	Color.RED,
	Color.BLUE,
	Color.GREEN,
	Color.YELLOW,
	Color.ORANGE,
	Color.PURPLE,
	Color.CYAN,
	Color.MAGENTA,
	Color(1.0, 0.5, 0.0),  # Orange foncé
	Color(0.5, 0.0, 0.5),  # Violet foncé
]

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
	
	# Assigner une couleur unique si le joueur n'en a pas déjà une
	if not players[id].has("color"):
		players[id]["color"] = _get_available_color()
	
	if is_host:
		rpc("_sync_lobby_data", players)

# Fonction pour obtenir une couleur disponible (non utilisée)
func _get_available_color() -> Color:
	var used_colors = []
	
	# Collecter toutes les couleurs déjà utilisées
	for player_id in players.keys():
		if players[player_id].has("color"):
			used_colors.append(players[player_id]["color"])
	
	# Trouver la première couleur disponible
	for color in PLAYER_COLORS:
		if not used_colors.has(color):
			return color
	
	# Si toutes les couleurs sont utilisées, retourner une couleur aléatoire
	return PLAYER_COLORS.pick_random()


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

func _assign_roles() -> void:
	if not is_host:
		return
	
	var player_ids = players.keys()
	var num_players = player_ids.size()
	
	if num_players < 2:
		print("Pas assez de joueurs pour assigner les rôles")
		return
	
	# Calculer le nombre de loups-garous (environ 1/4 des joueurs, minimum 1)
	var num_werewolves = max(1, num_players / 4)
	if num_players <= 4:
		num_werewolves = 1
	elif num_players <= 8:
		num_werewolves = 2
	
	# Mélanger les IDs pour une distribution aléatoire
	var shuffled_ids = player_ids.duplicate()
	shuffled_ids.shuffle()
	
	# Assigner les rôles
	for i in range(shuffled_ids.size()):
		var player_id = shuffled_ids[i]
		if i < num_werewolves:
			players[player_id]["role"] = ROLE_WEREWOLF
		else:
			players[player_id]["role"] = ROLE_VILLAGEOIS
	
	# Synchroniser les rôles avec tous les clients
	rpc("_sync_lobby_data", players)
	print("Rôles assignés: ", players)

func start_game():
	if is_host:
		_assign_roles()
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

func get_player_role(player_id: int) -> String:
	if players.has(player_id):
		return players[player_id].get("role", ROLE_VILLAGEOIS)
	return ROLE_VILLAGEOIS

# Fonction pour vérifier si un joueur est loup-garou
func is_werewolf(player_id: int) -> bool:
	return get_player_role(player_id) == ROLE_WEREWOLF

# Fonction pour obtenir tous les loups-garous
func get_werewolves() -> Array:
	var werewolves = []
	for player_id in players.keys():
		if is_werewolf(player_id):
			werewolves.append(player_id)
	return werewolves

# Fonction pour vérifier si un joueur est mort
func is_player_dead(player_id: int) -> bool:
	if players.has(player_id):
		return players[player_id].get("is_dead", false)
	return false

# Fonction pour obtenir tous les joueurs vivants
func get_alive_players() -> Array:
	var alive = []
	for player_id in players.keys():
		if not is_player_dead(player_id):
			alive.append(player_id)
	return alive

# Fonction pour obtenir tous les joueurs morts
func get_dead_players() -> Array:
	var dead = []
	for player_id in players.keys():
		if is_player_dead(player_id):
			dead.append(player_id)
	return dead

# Fonction principale pour tuer un joueur
@rpc("any_peer", "call_local", "reliable")
func request_kill_player(target_player_id: int) -> void:
	if not get_tree().get_multiplayer().is_server():
		return
	
	var killer_id: int = multiplayer.get_remote_sender_id()
	if killer_id == 0:
		killer_id = multiplayer.get_unique_id()
	
	# Vérifications de sécurité
	if not players.has(target_player_id):
		print("Erreur: Joueur cible %d n'existe pas" % target_player_id)
		return
	
	if is_player_dead(target_player_id):
		print("Erreur: Joueur %d est déjà mort" % target_player_id)
		return
	
	if killer_id == target_player_id:
		print("Erreur: Un joueur ne peut pas se tuer lui-même")
		return
	
	# Marquer le joueur comme mort
	players[target_player_id]["is_dead"] = true
	
	# Synchroniser avec tous les clients
	rpc("_sync_lobby_data", players)
	
	# Désactiver le joueur dans la scène (jouer l'animation death)
	rpc("kill_player_in_scene", target_player_id)
	
	print("Joueur %d a été tué par %d" % [target_player_id, killer_id])

# RPC pour désactiver le joueur dans la scène (remplacer l'ancienne version)
@rpc("any_peer", "call_local", "reliable")
func kill_player_in_scene(player_id: int) -> void:
	var player_node_path = "TestScene/Players/Player_" + str(player_id) 
	var root = get_tree().get_root()
	var player_node = root.get_node_or_null(player_node_path) 
	
	if player_node:
		# Appeler la fonction RPC sur le joueur pour jouer l'animation death
		player_node.rpc("play_death_animation")
		print("Joueur %d va jouer l'animation death" % player_id)
	else:
		push_error("Joueur %d non trouvé dans la scène" % player_id)