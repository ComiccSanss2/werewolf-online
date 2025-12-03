extends Control

@onready var players_list := $CanvasLayer/PlayersList
@onready var start_button := $CanvasLayer/ButtonStart
@onready var color_picker_panel := $CanvasLayer/ColorPanel
@onready var color_grid := $CanvasLayer/ColorPanel/GridContainer
@onready var open_color_btn := $CanvasLayer/ColorButton

const COLORS_CHOICES = [Color.WHITE, Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.ORANGE, Color.PURPLE, Color.CYAN, Color.MAGENTA, Color.BLACK, Color.BROWN]

func _ready() -> void:
	start_button.visible = NetworkHandler.is_host # Assure-toi d'avoir is_host dans Network ou utilise multiplayer.is_server()
	NetworkHandler.lobby_players_updated.connect(_update_list)
	NetworkHandler.game_started.connect(_on_game_started)
	
	open_color_btn.pressed.connect(_on_open_color_picker)
	_generate_color_buttons()
	color_picker_panel.visible = false
	_update_list(NetworkHandler.players)

func _generate_color_buttons():
	for child in color_grid.get_children():
		child.queue_free()
	
	for col in COLORS_CHOICES:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(40, 40)
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color.WHITE # Base blanche
		style.set_corner_radius_all(4) # Optionnel : coins arrondis
		
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.modulate = col 
		btn.pressed.connect(func(): _on_color_chosen(col))
		color_grid.add_child(btn)

func _on_open_color_picker():
	color_picker_panel.visible = !color_picker_panel.visible

# --- LOGIQUE DÉPLACÉE ICI ---

func _on_color_chosen(color: Color):
	# On appelle le RPC qui est maintenant DANS LE LOBBY
	rpc("update_player_color_rpc", color)
	color_picker_panel.visible = false

# Le RPC est reçu par les Lobbies de tout le monde
@rpc("any_peer", "call_local", "reliable")
func update_player_color_rpc(new_color: Color):
	var sender_id = multiplayer.get_remote_sender_id()
	
	# On met à jour la mémoire globale (Network)
	if NetworkHandler.players.has(sender_id):
		NetworkHandler.players[sender_id]["color"] = new_color
		
		# On force la mise à jour visuelle de la liste
		_update_list(NetworkHandler.players)

# -----------------------------

func _update_list(players: Dictionary) -> void:
	players_list.text = "Joueurs :\n"
	
	for id in players.keys():
		var p_name = players[id]["name"]
		var random_col = COLORS_CHOICES.pick_random()
		
		var p_color = players[id].get("color", random_col)
		
		var hex_code = p_color.to_html(false)
		
		players_list.text += "[color=#%s]- %s[/color]\n" % [hex_code, p_name]

func _on_StartButton_pressed() -> void:
	if multiplayer.is_server():
		NetworkHandler.start_game() # Assure-toi que cette fonction existe dans Network

func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://test_scene.tscn")
