extends Control

# Références aux nœuds de l'interface
@onready var players_list := $CanvasLayer/PlayersList
@onready var start_button: TextureButton = $CanvasLayer/ButtonStart
@onready var color_picker_panel := $CanvasLayer/ColorPanel
@onready var color_grid := $CanvasLayer/ColorPanel/GridContainer
@onready var open_color_btn := $CanvasLayer/ColorButton
# --- AJOUT DU BOUTON MENU ---
@onready var menu_button := $CanvasLayer/MenuButton 
# ----------------------------

# --- AUDIO ---
@onready var sfx_player: AudioStreamPlayer = $SFX_Player
var sound_click = preload("res://assets/sfx/clickbutton.wav")

# Utilise la même palette que NetworkHandler
const COLORS_CHOICES = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.ORANGE,
	Color.PURPLE, Color.CYAN, Color.MAGENTA, Color.PINK, Color.LIME_GREEN,
	Color(1.0, 0.5, 0.0), Color(0.5, 0.0, 0.5), Color(0.0, 0.5, 0.5),
	Color(1.0, 0.75, 0.8), Color(0.5, 1.0, 0.5), Color(0.75, 0.5, 1.0)
]

func _ready() -> void:
	if start_button:
		start_button.visible = NetworkHandler.is_host
		# SON BOUTON START
		start_button.pressed.connect(func(): _play_sound(sound_click))
	
	NetworkHandler.lobby_players_updated.connect(_update_list)
	NetworkHandler.game_started.connect(_on_game_started)
	
	if open_color_btn:
		open_color_btn.pressed.connect(_on_open_color_picker)
		# SON BOUTON OUVRIR COULEUR
		open_color_btn.pressed.connect(func(): _play_sound(sound_click))

	# --- CONNEXION BOUTON MENU ---
	if menu_button:
		menu_button.pressed.connect(_on_MenuButton_pressed)
		menu_button.pressed.connect(func(): _play_sound(sound_click))
	# -----------------------------
		
	_generate_color_buttons()
	if color_picker_panel:
		color_picker_panel.visible = false
	
	_update_list(NetworkHandler.players)

# Fonction utilitaire pour jouer le son
func _play_sound(stream: AudioStream):
	if sfx_player:
		sfx_player.stream = stream
		# Petite variation de pitch pour le "Juice"
		sfx_player.pitch_scale = randf_range(0.9, 1.1)
		sfx_player.play()

# Génère les boutons de sélection de couleur
func _generate_color_buttons():
	if not color_grid:
		return
	
	for child in color_grid.get_children():
		child.queue_free()
	
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
		
		# Connexion Logique
		btn.pressed.connect(func(): _on_color_chosen(col))
		# Connexion Sonore (SON CLIC SUR LES COULEURS)
		btn.pressed.connect(func(): _play_sound(sound_click))
		
		color_grid.add_child(btn)

# Affiche ou cache le panneau de sélection de couleur
func _on_open_color_picker():
	if color_picker_panel:
		color_picker_panel.visible = !color_picker_panel.visible

# Appelé quand un joueur choisit une couleur
func _on_color_chosen(color: Color):
	rpc("update_player_color_rpc", color)
	if color_picker_panel:
		color_picker_panel.visible = false

# RPC : Met à jour la couleur d'un joueur
@rpc("any_peer", "call_local", "reliable")
func update_player_color_rpc(new_color: Color):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	
	if not NetworkHandler.players.has(sender_id):
		return
	
	NetworkHandler.players[sender_id]["color"] = new_color
	
	if NetworkHandler.is_host:
		NetworkHandler.rpc("_sync_lobby_data", NetworkHandler.players)
	else:
		_update_list(NetworkHandler.players)

# Met à jour l'affichage de la liste des joueurs avec leurs couleurs
func _update_list(players: Dictionary) -> void:
	if not players_list:
		return
	var text = "Players :\n"
	for p in players.values():
		var hex = p.get("color", Color.WHITE).to_html(false)
		text += "[color=#%s]- %s[/color]\n" % [hex, p["name"]]
	players_list.text = text

# Démarre la partie (uniquement pour l'hôte)
func _on_StartButton_pressed() -> void:
	if multiplayer.is_server():
		NetworkHandler.start_game()

# --- RETOUR AU MENU (NOUVEAU) ---
func _on_MenuButton_pressed() -> void:
	NetworkHandler.stop_network()
	
	# 2. On attend un tout petit peu pour le son "clic"
	await get_tree().create_timer(0.15).timeout
	
	get_tree().change_scene_to_file("res://main_menu.tscn")

# Change de scène vers le jeu quand la partie démarre
func _on_game_started() -> void:
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://loading_screen.tscn")
