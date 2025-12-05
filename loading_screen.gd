extends Control

@onready var label = $LoadingLabel 

func _ready():

	await get_tree().create_timer(3.0).timeout # 3 secondes de chargement artificiel
	
	_load_game()

func _load_game():
	# On change vers la scène de jeu
	# IMPORTANT : Assure-toi du nom EXACT du fichier !
	get_tree().change_scene_to_file("res://test_scene.tscn")
