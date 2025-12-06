extends Control

const LOAD_TIME = 3.0 # Tu peux réduire ça à 1.0 ou 2.0 maintenant

func _ready():
	print("--- LOADING SCREEN ---")
	
	# ----------------------------------------------
	
	await get_tree().create_timer(LOAD_TIME).timeout
	_go_to_game()

func _go_to_game():
	# Assure-toi du chemin exact !
	get_tree().change_scene_to_file("res://test_scene.tscn")
