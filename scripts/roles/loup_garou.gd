class_name LoupGarou
extends Role

# Rôle : Loup-Garou
# Peut tuer un villageois chaque nuit

var target_vote: int = -1  # Vote du loup pour la victime de la nuit

func _init():
	role_name = "Loup-Garou"
	description = "Vous êtes un loup-garou ! Chaque nuit, vous devez éliminer un villageois avec les autres loups. Votre objectif : éliminer tous les villageois."
	team = "loup"
	is_alive = true
	can_vote = true

# Action de jour : le loup-garou vote comme tout le monde
func day_action() -> Dictionary:
	if not is_alive:
		return {"success": false, "message": "Vous êtes mort, vous ne pouvez pas agir."}
	
	return {
		"success": true,
		"action": "vote",
		"message": "Vous pouvez voter (et faire semblant d'être innocent...)."
	}

# Action de nuit : le loup-garou choisit une victime
func night_action() -> Dictionary:
	if not is_alive:
		return {"success": false, "message": "Vous êtes mort."}
	
	return {
		"success": true,
		"action": "kill",
		"message": "Choisissez une victime avec les autres loups-garous...",
		"can_target": true
	}

# Pouvoir spécial : voter pour tuer quelqu'un la nuit
func special_power(target_id: int = -1) -> Dictionary:
	if not is_alive:
		return {"success": false, "message": "Vous êtes mort."}
	
	if target_id == -1:
		return {"success": false, "message": "Vous devez choisir une cible."}
	
	target_vote = target_id
	
	return {
		"success": true,
		"message": "Vous avez voté pour éliminer le joueur " + str(target_id),
		"target": target_id
	}

# Reset le vote de nuit
func reset_night_vote():
	target_vote = -1

