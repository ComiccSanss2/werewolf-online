extends Control

signal vote_cast(target_id) 

@onready var container = $GridContainer 

# On précharge la police (Assure-toi que le chemin est bon)
const FONT = preload("res://assets/fonts/Daydream DEMO.otf")

func _ready():
	visible = false 

# On passe le dictionnaire COMPLET des joueurs
func setup_voting(all_players: Dictionary):
	# 1. Nettoyage des anciens boutons
	for child in container.get_children():
		child.queue_free()
	
	# 2. Configuration de la Grille
	if all_players.size() > 4:
		container.columns = 2
	else:
		container.columns = 1
	
	var my_id = multiplayer.get_unique_id()
	
	for id in all_players:
		var p_data = all_players[id]
		var btn = Button.new()
		
		# --- CONSTRUCTION DU TEXTE ---
		var btn_text = p_data["name"]
		
		# Si c'est moi
		if id == my_id:
			btn_text += " (You)"
			
		# Si le joueur est mort
		if NetworkHandler.is_player_dead(id):
			btn_text += " [Dead]"
			
		btn.text = btn_text
		
		# --- STYLE & FONT ---
		btn.add_theme_font_override("font", FONT)
		btn.add_theme_font_size_override("font_size", 16) 
		btn.custom_minimum_size = Vector2(200, 60)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER 
		
		# --- GESTION COULEUR & ÉTAT ---
		var p_color = p_data.get("color", Color.WHITE)
		
		if NetworkHandler.is_player_dead(id):
			btn.disabled = true
			btn.modulate = Color.GRAY 
		else:
			btn.modulate = p_color
			
			if id == my_id:
				btn.disabled = true
				btn.modulate.a = 0.7 
			else:
				btn.pressed.connect(func(): _on_vote_button_pressed(id))
		
		container.add_child(btn)
	
	visible = true 

func _on_vote_button_pressed(target_id):
	print("J'ai voté pour : ", target_id)
	vote_cast.emit(target_id)
	
	for btn in container.get_children():
		btn.disabled = true
