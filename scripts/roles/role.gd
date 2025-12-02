class_name Role
extends RefCounted

# Classe de base pour tous les rôles du jeu

var role_name: String = "Unknown"
var description: String = ""
var team: String = "village"  # "village" ou "loup"
var is_alive: bool = true
var can_vote: bool = true
var player_id: int = -1

# Fonction appelée pendant la phase de jour
func day_action() -> Dictionary:
	if not is_alive:
		return {"success": false, "message": "Vous êtes mort, vous ne pouvez pas agir."}
	
	return {
		"success": true,
		"action": "vote",
		"message": "Vous pouvez voter."
	}

# Fonction appelée pendant la phase de nuit
func night_action() -> Dictionary:
	if not is_alive:
		return {"success": false, "message": "Vous êtes mort."}
	
	return {
		"success": true,
		"action": "sleep",
		"message": "Vous dormez..."
	}

# Pouvoir spécial du rôle (si applicable)
func special_power(target_id: int = -1) -> Dictionary:
	return {
		"success": false,
		"message": "Ce rôle n'a pas de pouvoir spécial."
	}

# Fonction appelée quand le joueur meurt
func on_death():
	is_alive = false
	can_vote = false

# Retourne les infos du rôle
func get_info() -> Dictionary:
	return {
		"name": role_name,
		"description": description,
		"team": team,
		"is_alive": is_alive,
		"can_vote": can_vote
	}

