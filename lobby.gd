extends Control

# Références aux nœuds de l'interface
@onready var players_list := $CanvasLayer/PlayersList
@onready var start_button: TextureButton = $CanvasLayer/ButtonStart
@onready var color_picker_panel := $CanvasLayer/ColorPanel
@onready var color_grid := $CanvasLayer/ColorPanel/GridContainer
@onready var open_color_btn := $CanvasLayer/ColorButton
@onready var menu_button := $CanvasLayer/MenuButton 
@onready var ip_label := $CanvasLayer/IPLabel 

# --- AUDIO ---
@onready var sfx_player: AudioStreamPlayer = $SFX_Player
var sound_click = preload("res://assets/sfx/clickbutton.wav")

const COLORS_CHOICES = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.ORANGE,
	Color.PURPLE, Color.CYAN, Color.MAGENTA, Color.PINK, Color.LIME_GREEN,
	Color(1.0, 0.5, 0.0), Color(0.5, 0.0, 0.5), Color(0.0, 0.5, 0.5),
	Color(1.0, 0.75, 0.8), Color(0.5, 1.0, 0.5), Color(0.75, 0.5, 1.0)
]

func _ready() -> void:
	if start_button:
		start_button.visible = NetworkHandler.is_host
		start_button.pressed.connect(func(): _play_sound(sound_click))
	
	NetworkHandler.lobby_players_updated.connect(_update_list)
	NetworkHandler.game_started.connect(_on_game_started)
	
	# --- CONNEXION UPNP ---
	if not NetworkHandler.upnp_completed.is_connected(_on_upnp_completed):
		NetworkHandler.upnp_completed.connect(_on_upnp_completed)
	
	# Gestion initiale du Label IP
	if ip_label:
		if NetworkHandler.is_host:
			if NetworkHandler.public_ip_address != "":
				ip_label.text = "Public IP : " + NetworkHandler.public_ip_address
			else:
				ip_label.text = "Looking for IP..."
		else:
			ip_label.visible = false

	# Connexion déconnexion serveur
	get_tree().get_multiplayer().server_disconnected.connect(_on_server_disconnected)
	
	if open_color_btn:
		open_color_btn.pressed.connect(_on_open_color_picker)
		open_color_btn.pressed.connect(func(): _play_sound(sound_click))

	if menu_button:
		menu_button.pressed.connect(_on_MenuButton_pressed)
		menu_button.pressed.connect(func(): _play_sound(sound_click))
		
	_generate_color_buttons()
	if color_picker_panel:
		color_picker_panel.visible = false
	
	_update_list(NetworkHandler.players)

# --- CALLBACK UPNP ---
func _on_upnp_completed(ip_address: String):
	if ip_label and NetworkHandler.is_host:
		ip_label.text = "PUBLIC IP : " + ip_address

func _on_server_disconnected():
	print("Host disconnected, returning to main menu...")
	_return_to_main_menu()

func _play_sound(stream: AudioStream):
	if sfx_player:
		sfx_player.stream = stream
		sfx_player.pitch_scale = randf_range(0.9, 1.1)
		sfx_player.play()

func _generate_color_buttons():
	if not color_grid: return
	for child in color_grid.get_children(): child.queue_free()
	color_grid.columns = 4
	for col in COLORS_CHOICES:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(40, 40)
		var style = StyleBoxFlat.new()
		style.bg_color = col
		style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.pressed.connect(func(): _on_color_chosen(col))
		btn.pressed.connect(func(): _play_sound(sound_click))
		color_grid.add_child(btn)

func _on_open_color_picker():
	if color_picker_panel: color_picker_panel.visible = !color_picker_panel.visible

func _on_color_chosen(color: Color):
	rpc("update_player_color_rpc", color)
	if color_picker_panel: color_picker_panel.visible = false

@rpc("any_peer", "call_local", "reliable")
func update_player_color_rpc(new_color: Color):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()
	if not NetworkHandler.players.has(sender_id): return
	NetworkHandler.players[sender_id]["color"] = new_color
	
	if NetworkHandler.is_host:
		NetworkHandler.rpc("_sync_lobby_data", NetworkHandler.players)
	else:
		_update_list(NetworkHandler.players)

func _update_list(players: Dictionary) -> void:
	if not players_list: return
	var text = "Players :\n"
	for p in players.values():
		var hex = p.get("color", Color.WHITE).to_html(false)
		text += "[color=#%s]- %s[/color]\n" % [hex, p["name"]]
	players_list.text = text

func _on_StartButton_pressed() -> void:
	if multiplayer.is_server():
		NetworkHandler.start_game()

func _on_MenuButton_pressed() -> void:
	_return_to_main_menu()

func _return_to_main_menu() -> void:
	NetworkHandler.stop_network()
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_game_started() -> void:
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://loading_screen.tscn")
