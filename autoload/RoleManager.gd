extends Node

# Gestionnaire des rôles du jeu
# Gère l'attribution aléatoire des rôles aux joueurs

# Dictionnaire : peer_id -> Role
var player_roles := {}

# Configuration du nombre de loups-garous selon le nombre de joueurs
var wolves_config := {
	3: 1,   # 3 joueurs = 1 loup
	4: 1,   # 4 joueurs = 1 loup
	5: 1,   # 5 joueurs = 1 loup
	6: 2,   # 6 joueurs = 2 loups
	7: 2,   # 7 joueurs = 2 loups
	8: 2,   # 8 joueurs = 2 loups
	9: 3,   # 9 joueurs = 3 loups
	10: 3,  # 10 joueurs = 3 loups
}

###################################################
# ATTRIBUTION DES RÔLES
###################################################

# Attribue les rôles de manière aléatoire
func assign_roles(player_ids: Array) -> Dictionary:
	player_roles.clear()
	
	var num_players = player_ids.size()
	if num_players < 3:
		return {
			"success": false,
			"message": "Il faut au moins 3 joueurs pour jouer !"
		}
	
	# Déterminer le nombre de loups-garous
	var num_wolves = wolves_config.get(num_players, max(1, num_players / 3))
	var num_villagers = num_players - num_wolves
	
	print("ROLE MANAGER: %d joueurs, %d loups, %d villageois" % [num_players, num_wolves, num_villagers])
	
	# Créer la liste des rôles à distribuer
	var roles_to_assign = []
	
	# Ajouter les loups-garous
	for i in range(num_wolves):
		roles_to_assign.append("loup")
	
	# Ajouter les villageois
	for i in range(num_villagers):
		roles_to_assign.append("villageois")
	
	# Mélanger aléatoirement
	roles_to_assign.shuffle()
	
	# Assigner les rôles aux joueurs
	for i in range(player_ids.size()):
		var peer_id = player_ids[i]
		var role_type = roles_to_assign[i]
		
		var role = _create_role(role_type, peer_id)
		player_roles[peer_id] = role
		
		print("ROLE MANAGER: Joueur %d -> %s" % [peer_id, role.role_name])
	
	return {
		"success": true,
		"num_wolves": num_wolves,
		"num_villagers": num_villagers
	}

# Crée une instance de rôle
func _create_role(role_type: String, peer_id: int) -> Role:
	var role: Role
	
	match role_type:
		"loup":
			role = LoupGarou.new()
		"villageois":
			role = Villageois.new()
		_:
			role = Villageois.new()  # Par défaut
	
	role.player_id = peer_id
	return role

###################################################
# GETTERS
###################################################

# Récupère le rôle d'un joueur
func get_player_role(peer_id: int) -> Role:
	return player_roles.get(peer_id, null)

# Vérifie si un joueur est un loup-garou
func is_werewolf(peer_id: int) -> bool:
	var role = get_player_role(peer_id)
	return role != null and role.team == "loup"

# Vérifie si un joueur est vivant
func is_alive(peer_id: int) -> bool:
	var role = get_player_role(peer_id)
	return role != null and role.is_alive

# Récupère tous les loups-garous vivants
func get_alive_wolves() -> Array:
	var wolves = []
	for peer_id in player_roles:
		var role = player_roles[peer_id]
		if role.team == "loup" and role.is_alive:
			wolves.append(peer_id)
	return wolves

# Récupère tous les villageois vivants
func get_alive_villagers() -> Array:
	var villagers = []
	for peer_id in player_roles:
		var role = player_roles[peer_id]
		if role.team == "village" and role.is_alive:
			villagers.append(peer_id)
	return villagers

# Vérifie les conditions de victoire
func check_win_condition() -> Dictionary:
	var alive_wolves = get_alive_wolves()
	var alive_villagers = get_alive_villagers()
	
	if alive_wolves.size() == 0:
		return {
			"game_over": true,
			"winner": "village",
			"message": "Les villageois ont gagné ! Tous les loups-garous sont éliminés."
		}
	
	if alive_villagers.size() <= alive_wolves.size():
		return {
			"game_over": true,
			"winner": "loup",
			"message": "Les loups-garous ont gagné ! Ils sont aussi nombreux que les villageois."
		}
	
	return {
		"game_over": false
	}

###################################################
# ACTIONS
###################################################

# Tue un joueur
func kill_player(peer_id: int):
	var role = get_player_role(peer_id)
	if role:
		role.on_death()
		print("ROLE MANAGER: Joueur %d (%s) est mort" % [peer_id, role.role_name])

# Réinitialise tous les rôles
func reset_all():
	player_roles.clear()
	print("ROLE MANAGER: Reset complet")

