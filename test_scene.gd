extends Node2D

var PlayerScene = preload("res://player.tscn")
var player_sprite_frames = preload("res://player_frames.tres")

@onready var players_root = $Players
# On récupère tous les spawns (Spawn1... Spawn8)
@onready var spawn_points = $SpawnPoints.get_children()
@onready var bodies_container = $DeadBodies

# UI et timers
@onready var game_timer: Timer = $GameTimer
@onready var voting_timer: Timer = $VotingTimer
@onready var ui_layer: CanvasLayer = $UI_Layer
@onready var timer_label: Label = $UI_Layer/TimerLabel
@onready var voting_ui: Control = $UI_Layer/VotingScreen
@onready var game_over_ui: Control = $UI_Layer/GameOverScreen
@onready var announcement_label: Label = $UI_Layer/AnnouncementLabel 
@onready var report_label_ui: Label = $UI_Layer/ReportLabel

const GAME_DURATION = 180.0 
const VOTE_DURATION = 60.0  

var current_votes: Dictionary = {}
var is_voting_phase: bool = false
var is_intermission_phase: bool = false

func _ready() -> void:
	self.name = "TestScene"
	print("--- TEST SCENE LOADED ---")
	
	var mp = get_tree().get_multiplayer()
	
	if mp.peer_connected.is_connected(_on_player_connected): mp.peer_connected.disconnect(_on_player_connected)
	if mp.peer_disconnected.is_connected(_on_player_disconnected): mp.peer_disconnected.disconnect(_on_player_disconnected)
	if mp.server_disconnected.is_connected(_on_server_disconnected): mp.server_disconnected.disconnect(_on_server_disconnected)
	
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)
	mp.server_disconnected.connect(_on_server_disconnected)
	
	if not NetworkHandler.game_over.is_connected(_on_game_over):
		NetworkHandler.game_over.connect(_on_game_over)
	
	voting_ui.visible = false
	game_over_ui.visible = false
	timer_label.visible = true
	if announcement_label: announcement_label.visible = false
	if report_label_ui: report_label_ui.visible = false
	
	if voting_ui.has_signal("vote_cast"):
		if not voting_ui.vote_cast.is_connected(_on_local_player_voted):
			voting_ui.vote_cast.connect(_on_local_player_voted)
	
	if game_over_ui.has_signal("go_to_menu"):
		if not game_over_ui.go_to_menu.is_connected(_on_go_back_to_menu):
			game_over_ui.go_to_menu.connect(_on_go_back_to_menu)
	
	if mp.is_server():
		if not game_timer.timeout.is_connected(_on_game_timer_ended):
			game_timer.timeout.connect(_on_game_timer_ended)
		if not voting_timer.timeout.is_connected(_on_voting_timer_ended):
			voting_timer.timeout.connect(_on_voting_timer_ended)
		game_timer.one_shot = true
		voting_timer.one_shot = true
		
		# Le Host se spawn lui-même au début
		_handle_new_player_ready(1)
		start_game_timer()
	else:
		await get_tree().process_frame
		rpc_id(1, "client_ready_for_game")

func _process(_delta: float) -> void:
	var t = 0.0
	var col = Color.WHITE
	
	if is_voting_phase:
		t = voting_timer.time_left
		col = Color.YELLOW
		timer_label.text = "VOTE: %02d" % int(t)
	elif is_intermission_phase:
		t = voting_timer.time_left
		col = Color.ORANGE
		timer_label.text = "STARTING: %d" % int(t)
	else:
		if not game_timer.is_stopped():
			t = game_timer.time_left
			timer_label.text = "%02d:%02d" % [floor(t/60), int(t)%60]
			if t < 10: col = Color.RED
	
	timer_label.modulate = col

func set_report_label_visible(is_visible: bool):
	if report_label_ui:
		report_label_ui.visible = is_visible

# ========== GESTION DES SPAWNS (NOUVEAU) ==========

# Fonction utilitaire pour trouver un spawn libre (Pour les nouveaux arrivants)
func _get_free_spawn_point() -> Vector2:
	# On liste toutes les positions possibles
	var available_positions = []
	for sp in spawn_points:
		available_positions.append(sp.global_position)
	
	# On regarde où sont les joueurs actuels
	var used_positions = []
	for child in players_root.get_children():
		used_positions.append(child.global_position)
	
	# On mélange pour que ce soit random
	available_positions.shuffle()
	
	# On cherche une position qui n'est pas trop proche d'un joueur existant
	for pos in available_positions:
		var is_taken = false
		for used in used_positions:
			if pos.distance_to(used) < 50.0: # Si moins de 50 pixels, c'est pris
				is_taken = true
				break
		if not is_taken:
			return pos
	
	# Si tout est pris (rare), on retourne une random quand même
	return available_positions[0] if available_positions.size() > 0 else Vector2.ZERO

# Fonction pour mélanger TOUT LE MONDE (Après un vote)
func _reshuffle_all_players_positions():
	if not multiplayer.is_server(): return
	
	# 1. On crée une liste de toutes les positions de spawn disponibles
	var all_positions = []
	for sp in spawn_points:
		all_positions.append(sp.global_position)
	
	# 2. On mélange cette liste
	all_positions.shuffle()
	
	# 3. On attribue une position unique à chaque joueur vivant
	var index = 0
	for player in players_root.get_children():
		# (Optionnel : ne pas téléporter les morts s'ils sont spectateurs, 
		# mais c'est mieux de les bouger aussi pour ne pas qu'ils restent sur leur cadavre)
		
		if index < all_positions.size():
			# On appelle le RPC sur le joueur pour le téléporter
			player.rpc("force_teleport", all_positions[index])
			index += 1

# ========== Gestion des timers ==========

func start_game_timer():
	# 1. Nettoyage des cadavres
	for child in bodies_container.get_children():
		child.queue_free()
		
	is_voting_phase = false
	is_intermission_phase = false
	
	# --- MELANGE DES JOUEURS ICI ---
	if multiplayer.is_server():
		_reshuffle_all_players_positions()
	# -------------------------------
	
	NetworkHandler.is_gameplay_active = true
	
	if report_label_ui: report_label_ui.visible = false
	NetworkHandler.reset_night_actions()
	game_timer.start(GAME_DURATION)
	rpc("sync_game_timer", GAME_DURATION)

@rpc("call_local", "reliable")
func sync_game_timer(t: float):
	is_voting_phase = false
	is_intermission_phase = false
	NetworkHandler.is_gameplay_active = true
	
	voting_ui.visible = false
	timer_label.visible = true
	voting_timer.stop()
	game_timer.start(t)
	for child in bodies_container.get_children():
		child.queue_free()

func _on_game_timer_ended():
	if multiplayer.is_server():
		current_votes.clear()
		rpc("start_voting_phase")

func trigger_emergency_meeting():
	if not multiplayer.is_server(): return
	game_timer.stop()
	current_votes.clear()
	rpc("start_voting_phase")

# ========== Phase de vote ==========

@rpc("call_local", "reliable")
func start_voting_phase():
	NetworkHandler.is_gameplay_active = false
	is_voting_phase = true
	timer_label.visible = true
	
	if report_label_ui: report_label_ui.visible = false
	
	if multiplayer.is_server():
		voting_timer.start(VOTE_DURATION)
		if voting_timer.timeout.is_connected(_on_intermission_ended):
			voting_timer.timeout.disconnect(_on_intermission_ended)
		if not voting_timer.timeout.is_connected(_on_voting_timer_ended):
			voting_timer.timeout.connect(_on_voting_timer_ended)
		rpc("sync_voting_timer", VOTE_DURATION)
	
	if NetworkHandler.is_player_dead(multiplayer.get_unique_id()):
		voting_ui.visible = false
		return

	var alive = {}
	for id in NetworkHandler.players:
		if not NetworkHandler.is_player_dead(id):
			alive[id] = NetworkHandler.players[id]
	voting_ui.setup_voting(alive)
	voting_ui.visible = true

@rpc("call_local", "reliable")
func sync_voting_timer(t: float):
	is_voting_phase = true
	is_intermission_phase = false
	NetworkHandler.is_gameplay_active = false
	voting_timer.start(t)

@rpc("call_local", "reliable")
func start_intermission_phase():
	NetworkHandler.is_gameplay_active = false
	voting_ui.visible = false
	if announcement_label: announcement_label.visible = true
	
	is_voting_phase = false
	is_intermission_phase = true
	
	if multiplayer.is_server():
		if voting_timer.timeout.is_connected(_on_voting_timer_ended):
			voting_timer.timeout.disconnect(_on_voting_timer_ended)
		if not voting_timer.timeout.is_connected(_on_intermission_ended):
			voting_timer.timeout.connect(_on_intermission_ended)
		voting_timer.start(5.0)

func _on_intermission_ended():
	if voting_timer.timeout.is_connected(_on_intermission_ended):
		voting_timer.timeout.disconnect(_on_intermission_ended)
	if not voting_timer.timeout.is_connected(_on_voting_timer_ended):
		voting_timer.timeout.connect(_on_voting_timer_ended)
	
	rpc("hide_announcement")
	
	# C'est ici que le jeu reprend, et que le mélange se fera (voir start_game_timer)
	start_game_timer()

@rpc("call_local", "reliable")
func hide_announcement():
	if announcement_label: announcement_label.visible = false

func _on_local_player_voted(target_id):
	rpc_id(1, "submit_vote", target_id)

@rpc("any_peer", "call_local", "reliable")
func submit_vote(target_id):
	if not multiplayer.is_server(): return
	var vid = multiplayer.get_remote_sender_id()
	if NetworkHandler.is_player_dead(vid): return
	current_votes[vid] = target_id
	
	if current_votes.size() >= NetworkHandler.get_alive_players().size():
		if voting_timer.time_left > 10.0:
			voting_timer.start(10.0)
			rpc("sync_voting_timer", 10.0)

func _on_voting_timer_ended():
	if multiplayer.is_server():
		_resolve_voting_results()

func _resolve_voting_results():
	var counts = {}
	for t in current_votes.values(): counts[t] = counts.get(t, 0) + 1
	var max_v = 0; var elim = -1; var tie = false
	for t in counts:
		if counts[t] > max_v: max_v = counts[t]; elim = t; tie = false
		elif counts[t] == max_v: tie = true
	
	if elim != -1 and not tie:
		var p_data = NetworkHandler.players.get(elim, {})
		var p_name = p_data.get("name", "Inconnu")
		var p_role = p_data.get("role", "Inconnu")
		NetworkHandler.eliminate_player_by_vote(elim)
		rpc("rpc_voting_completed", elim, false, p_name, p_role)
	else:
		rpc("rpc_voting_completed", -1, true, "", "")
	
	rpc("start_intermission_phase")

@rpc("call_local", "reliable")
func rpc_voting_completed(_elim_id: int, tie: bool, player_name: String, player_role: String):
	voting_ui.visible = false
	is_voting_phase = false
	
	if announcement_label:
		if tie:
			announcement_label.text = "ÉGALITÉ - Personne n'est éliminé"
		elif _elim_id != -1:
			announcement_label.text = "%s (%s) a été éliminé !" % [player_name, player_role]
		announcement_label.visible = true

func _on_game_over(winner_role: String):
	NetworkHandler.is_gameplay_active = false
	game_timer.stop()
	voting_timer.stop()
	timer_label.visible = false
	voting_ui.visible = false
	if report_label_ui: report_label_ui.visible = false
	game_over_ui.show_victory(winner_role)

func _on_server_disconnected():
	NetworkHandler.is_gameplay_active = false
	set_process(false)
	game_timer.stop()
	voting_timer.stop()
	ui_layer.visible = true
	voting_ui.visible = false
	timer_label.visible = false
	if report_label_ui: report_label_ui.visible = false
	game_over_ui.show_disconnect()

func _on_go_back_to_menu():
	NetworkHandler.stop_network()
	get_tree().change_scene_to_file("res://MainMenu.tscn")

# --- SPAWN DES CADAVRES ---

var player_sprite_frames_res = preload("res://player_frames.tres") 

@rpc("call_local", "reliable")
func spawn_corpse_on_all(player_id: int, pos: Vector2, color: Color, is_flipped: bool):
	var corpse = AnimatedSprite2D.new()
	corpse.name = "Corpse_%d" % player_id
	corpse.sprite_frames = player_sprite_frames_res
	corpse.z_index = 1 
	corpse.modulate = color
	corpse.global_position = pos
	corpse.flip_h = is_flipped
	corpse.speed_scale = 1.0 
	
	if corpse.sprite_frames.has_animation("death"):
		corpse.play("death")
	else:
		corpse.play("idle-down")
		corpse.rotation_degrees = 90

	corpse.animation_finished.connect(func():
		if corpse.animation == "death":
			corpse.pause()
			corpse.frame = corpse.sprite_frames.get_frame_count("death") - 1
	)
	bodies_container.add_child(corpse)

@rpc("call_local", "reliable")
func remove_corpse_on_all(player_id: int, revive_pos: Vector2):
	var corpse = bodies_container.get_node_or_null("Corpse_%d" % player_id)
	if corpse: corpse.queue_free()
	
	var player = players_root.get_node_or_null("Player_%d" % player_id)
	if player: player.global_position = revive_pos

# --- HANDSHAKE ET SPAWN (Modifié pour Spawn Unique) ---

@rpc("any_peer", "call_local", "reliable")
func client_ready_for_game():
	if not multiplayer.is_server(): return
	var sid = multiplayer.get_remote_sender_id()
	_handle_new_player_ready(sid)

func _handle_new_player_ready(new_id: int):
	
	# 1. On trouve un spawn unique pour ce nouveau joueur
	var start_pos = _get_free_spawn_point()
	
	# 2. On le spawn
	_spawn_for_peer(new_id, start_pos)
	
	# 3. Back-spawn (les anciens vers le nouveau)
	if new_id != 1:
		for player in players_root.get_children():
			var pid = player.name.to_int() # "Player_123" -> 123
			# Attention : il faut parser le nom car on n'a pas l'ID direct ici
			var split = player.name.split("_")
			if split.size() > 1:
				pid = split[1].to_int()
			
			if pid != new_id:
				# On envoie la position actuelle du joueur existant
				spawn_player_on_all.rpc_id(new_id, pid, player.global_position)
		
		# Sync Etat du jeu
		if is_intermission_phase:
			rpc_id(new_id, "start_intermission_phase")
		elif is_voting_phase:
			rpc_id(new_id, "start_voting_phase")
			rpc_id(new_id, "sync_voting_timer", voting_timer.time_left)
		else:
			rpc_id(new_id, "sync_game_timer", game_timer.time_left)

func _on_player_connected(id: int): pass 

func _on_player_disconnected(id: int):
	if multiplayer.is_server():
		rpc("despawn_player_on_all", id)
		if current_votes.has(id):
			current_votes.erase(id)

func _spawn_for_peer(id: int, pos: Vector2):
	rpc("spawn_player_on_all", id, pos)

# MODIFIÉ : Ajout de l'argument 'spawn_pos'
@rpc("reliable", "call_local")
func spawn_player_on_all(id: int, spawn_pos: Vector2):
	var pname = "Player_%d" % id
	if players_root.has_node(pname): return
	
	var p = PlayerScene.instantiate()
	p.name = pname
	p.set_multiplayer_authority(id)
	
	# On utilise la position fournie par le serveur
	p.global_position = spawn_pos
	
	players_root.add_child(p)

@rpc("reliable", "call_local")
func despawn_player_on_all(id: int):
	var p = players_root.get_node_or_null("Player_%d" % id)
	if p: p.queue_free()
