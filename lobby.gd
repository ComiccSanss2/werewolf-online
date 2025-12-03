extends Control

@onready var players_list := $CanvasLayer/PlayersList
@onready var start_button := $CanvasLayer/ButtonStart

func _ready() -> void:
	start_button.visible = NetworkHandler.is_host
	NetworkHandler.lobby_players_updated.connect(_update_list)
	NetworkHandler.game_started.connect(_on_game_started)
	_update_list(NetworkHandler.players)

func _update_list(players: Dictionary) -> void:
	players_list.text = ""
	for id in players.keys():
		players_list.text += "- %s\n" % players[id]["name"]

func _on_StartButton_pressed() -> void:
	if NetworkHandler.is_host:
		NetworkHandler.start_game()

func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://test_scene.tscn")