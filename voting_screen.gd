extends Control

signal vote_cast(target_id) 

@onready var container = $GridContainer 

# On précharge la police (Vérifie le chemin)
const FONT = preload("res://assets/fonts/Daydream DEMO.otf")

func _ready():
	visible = false 

func setup_voting(players_alive: Dictionary):
	# Nettoyage
	for child in container.get_children():
		child.queue_free()
	
	# Configuration de la Grille
	if players_alive.size() > 4:
		container.columns = 2
	else:
		container.columns = 1
	
	var my_id = multiplayer.get_unique_id()
	
	for id in players_alive:
		var btn = Button.new()
		btn.text = players_alive[id]["name"]
		
		# --- STYLE & FONT ---
		btn.add_theme_font_override("font", FONT)
		btn.add_theme_font_size_override("font_size", 16) 
		btn.custom_minimum_size = Vector2(200, 60)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER 
		
		# --- LOGIQUE D'AUTO-VOTE ---
		if id == my_id:
			btn.disabled = true 
			btn.add_theme_color_override("font_disabled_color", Color(1, 1, 0, 0.5)) # Jaune transparent
		else:
			btn.pressed.connect(func(): _on_vote_button_pressed(id))
		# ---------------------------
		
		container.add_child(btn)
	
	visible = true 

func _on_vote_button_pressed(target_id):
	print("J'ai voté pour : ", target_id)
	vote_cast.emit(target_id)
	
	# On désactive TOUS les boutons après avoir voté
	for btn in container.get_children():
		btn.disabled = true
