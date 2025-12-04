extends Control

signal vote_cast(target_id) # Signal émis quand on clique sur quelqu'un

@onready var container = $GridContainer 

func _ready():
	visible = false # Caché par défaut

func setup_voting(players_alive: Dictionary):
	#  On nettoie les vieux boutons
	for child in container.get_children():
		child.queue_free()
	
	#  On crée un bouton pour chaque joueur vivant
	for id in players_alive:
		# On ne peut pas voter pour soi-même 

		
		var btn = Button.new()
		btn.text = players_alive[id]["name"]
		btn.custom_minimum_size = Vector2(200, 50)
		
		#  On connecte le signal "pressed" avec l'ID du joueur cible
		btn.pressed.connect(func(): _on_vote_button_pressed(id))
		
		container.add_child(btn)
	
	visible = true # On affiche l'écran

func _on_vote_button_pressed(target_id):
	# On cache l'interface ou on désactive les boutons pour ne pas voter 2 fois
	print("J'ai voté pour : ", target_id)
	vote_cast.emit(target_id)
	
	for btn in container.get_children():
		btn.disabled = true
