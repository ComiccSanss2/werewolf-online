class_name Villageois
extends Role

# Rôle : Villageois
# Le rôle de base, sans pouvoir spécial

func _init():
	role_name = "Villageois"
	description = "Un simple villageois sans pouvoir spécial. Votre objectif est d'éliminer tous les loups-garous."
	team = "village"
	is_alive = true
	can_vote = true

# Action de jour : le villageois peut voter
func day_action() -> Dictionary:
	if not is_alive:
		return {"success": false, "message": "Vous êtes mort, vous ne pouvez pas agir."}
	
	return {
		"success": true,
		"action": "vote",
		"message": "Vous pouvez voter pour éliminer un joueur suspect."
	}

# Action de nuit : le villageois dort (pas d'action)
func night_action() -> Dictionary:
	if not is_alive:
		return {"success": false, "message": "Vous êtes mort."}
	
	return {
		"success": true,
		"action": "sleep",
		"message": "Vous dormez paisiblement..."
	}
