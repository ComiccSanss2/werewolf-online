extends Node2D

# Scène principale du jeu - Gère les joueurs, le timer, les votes et les phases

var PlayerScene = preload("res://player.tscn")
var player_sprite_frames = preload("res://player_frames.tres")

@onready var players_root = $Players
@onready var spawn_points = $SpawnPoints.get_children()
@onready var bodies_container = $DeadBodies
var task_zones_container: Node2D

# UI et timers
@onready var game_timer: Timer = $GameTimer
@onready var voting_timer: Timer = $VotingTimer
@onready var ui_layer: CanvasLayer = $UI_Layer
@onready var timer_label: Label = $UI_Layer/TimerLabel
@onready var voting_ui: Control = $UI_Layer/VotingScreen
@onready var game_over_ui: Control = $UI_Layer/GameOverScreen
@onready var announcement_label: Label = $UI_Layer/AnnouncementLabel 
@onready var report_label_ui: Label = $UI_Layer/ReportLabel
@onready var report_announce_label: Label = $UI_Layer/ReportAnnounceLabel
@onready var task_counter_label: Label = Label.new()

# AUDIO
@onready var game_ost_player: AudioStreamPlayer = $GameOSTPlayer
@onready var voting_ost_player: AudioStreamPlayer = $VotingOSTPlayer

const GAME_DURATION = 120.0 
const VOTE_DURATION = 120.0 
const REPORT_DELAY = 15.0 
const FONT = preload("res://assets/fonts/Daydream DEMO.otf")

var current_votes: Dictionary = {}
var is_voting_phase: bool = false
var is_intermission_phase: bool = false
var can_report: bool = false

# --- VARIABLES QUÊTES ---
var rock_locations: Array[Vector2] = []
var plant_locations: Array[Vector2] = []

func _ready() -> void:
	self.name = "TestScene"
	print("--- TEST SCENE LOADED ---")
	
	task_zones_container = Node2D.new()
	task_zones_container.name = "TaskZonesContainer"
	add_child(task_zones_container)
	
	var mp = get_tree().get_multiplayer()
	
	if mp.peer_connected.is_connected(_on_player_connected): mp.peer_connected.disconnect(_on_player_connected)
	if mp.peer_disconnected.is_connected(_on_player_disconnected): mp.peer_disconnected.disconnect(_on_player_disconnected)
	if mp.server_disconnected.is_connected(_on_server_disconnected): mp.server_disconnected.disconnect(_on_server_disconnected)
	
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)
	mp.server_disconnected.connect(_on_server_disconnected)
	
	if not NetworkHandler.game_over.is_connected(_on_game_over):
		NetworkHandler.game_over.connect(_on_game_over)
	
	# Setup UI
	ui_layer.add_child(task_counter_label)
	task_counter_label.add_theme_font_override("font", FONT)
	task_counter_label.add_theme_font_size_override("font_size", 16)
	task_counter_label.add_theme_color_override("font_outline_color", Color.BLACK)
	task_counter_label.add_theme_constant_override("outline_size", 4)
	task_counter_label.anchors_preset = Control.PRESET_TOP_RIGHT
	task_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	task_counter_label.position = Vector2(1152 - 300, 20) 
	task_counter_label.size = Vector2(280, 100)
	
	# SCAN TACHES MANUELLES
	call_deferred("_scan_map_for_tasks")
	
	voting_ui.visible = false
	game_over_ui.visible = false
	timer_label.visible = true
	if announcement_label: announcement_label.visible = false
	if report_label_ui: report_label_ui.visible = false
	if report_announce_label: report_announce_label.visible = false
	
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
		
		_handle_new_player_ready(1)
		start_game_timer()
	else:
		await get_tree().process_frame
		await get_tree().physics_frame
		rpc_id(1, "client_ready_for_game")

# --- SCAN AREA2D ---
func _scan_map_for_tasks():
	rock_locations.clear()
	plant_locations.clear()
	
	# On récupère le dossier "Tasks" créé dans l'éditeur
	var tasks_node = get_node_or_null("Tasks")
	if tasks_node:
		for task in tasks_node.get_children():
			# On vérifie la propriété 'task_type' du script task_zone.gd
			if "task_type" in task:
				if task.task_type == "rock":
					rock_locations.append(task.global_position)
				elif task.task_type == "water":
					plant_locations.append(task.global_position)
	
	print("TÂCHES ENREGISTRÉES : %d Cailloux, %d Plantes." % [rock_locations.size(), plant_locations.size()])


func _process(_delta: float) -> void:
	var t = 0.0
	var col = Color.WHITE
	
	if is_voting_phase:
		t = voting_timer.time_left
		col = Color.YELLOW
		timer_label.text = "VOTE: %02d" % int(t)
		task_counter_label.visible = false
	elif is_intermission_phase:
		t = voting_timer.time_left
		col = Color.ORANGE
		timer_label.text = "STARTING: %d" % int(t)
		task_counter_label.visible = false
	else:
		if not game_timer.is_stopped():
			t = game_timer.time_left
			timer_label.text = "%02d:%02d" % [floor(t/60), int(t)%60]
			if t < 10: col = Color.RED
		
		task_counter_label.visible = true
		if NetworkHandler.players_tasks_progress.has(multiplayer.get_unique_id()):
			var prog = NetworkHandler.players_tasks_progress[multiplayer.get_unique_id()]
			var r = prog["rocks"]
			var w = prog["water"]
			
			var txt = "TASKS:\nCOLLECTING ROCKS: %d/%d\nWATERING FIELD: %d/%d" % [r, NetworkHandler.GOAL_ROCKS, w, NetworkHandler.GOAL_WATER]
			
			if prog["finished"]:
				txt += "\n(COMPLETED)"
				task_counter_label.modulate = Color.GREEN
			else:
				task_counter_label.modulate = Color.WHITE
				
			task_counter_label.text = txt
		else:
			task_counter_label.text = "TASKS:\nNONE (Werewolf)"
			task_counter_label.modulate = Color.RED
	
	timer_label.modulate = col

func set_report_label_visible(is_visible: bool):
	if report_label_ui:
		report_label_ui.visible = is_visible

func _transition_music(music_in: AudioStreamPlayer, music_out: AudioStreamPlayer, duration: float):
	const TARGET_DB_IN = -10.0 
	const TARGET_DB_OUT = -80.0 
	
	music_in.volume_db = TARGET_DB_OUT
	if not music_in.playing:
		music_in.play()
	
	var tween_in = create_tween()
	tween_in.tween_property(music_in, "volume_db", TARGET_DB_IN, duration)
	
	var tween_out = create_tween()
	tween_out.tween_property(music_out, "volume_db", TARGET_DB_OUT, duration)
	
	await tween_out.finished
	music_out.stop()

func _get_free_spawn_point() -> Vector2:
	var available_positions = []
	for sp in spawn_points: available_positions.append(sp.global_position)
	var used_positions = []
	for child in players_root.get_children(): used_positions.append(child.global_position)
	available_positions.shuffle()
	for pos in available_positions:
		var is_taken = false
		for used in used_positions:
			if pos.distance_to(used) < 50.0: is_taken = true; break
		if not is_taken: return pos
	return available_positions[0] if available_positions.size() > 0 else Vector2.ZERO

func _reshuffle_all_players_positions():
	if not multiplayer.is_server(): return
	var all_positions = []
	for sp in spawn_points: all_positions.append(sp.global_position)
	all_positions.shuffle()
	var index = 0
	for player in players_root.get_children():
		if index < all_positions.size():
			player.rpc("force_teleport", all_positions[index])
			index += 1

func start_game_timer():
	for child in bodies_container.get_children():
		child.queue_free()
	
	is_voting_phase = false
	is_intermission_phase = false
	can_report = false
	
	# IMPORTANT : On cache l'écran de victoire au cas où
	game_over_ui.visible = false
	
	if multiplayer.is_server():
		_reshuffle_all_players_positions()
	
	NetworkHandler.is_gameplay_active = true
	if report_label_ui: report_label_ui.visible = false
	if report_announce_label: report_announce_label.visible = false
	
	if multiplayer.is_server():
		NetworkHandler.init_tasks_for_game()
	
	NetworkHandler.reset_night_actions()
	game_timer.start(GAME_DURATION)
	rpc("sync_game_timer", GAME_DURATION)
	
	_transition_music(game_ost_player, voting_ost_player, 2.0)
	
	await get_tree().create_timer(REPORT_DELAY).timeout
	can_report = true
	rpc("enable_reports")

@rpc("call_local", "reliable")
func sync_game_timer(t: float):
	is_voting_phase = false
	is_intermission_phase = false
	can_report = false
	# On s'assure que le GameOver est caché chez le client aussi
	game_over_ui.visible = false
	
	NetworkHandler.is_gameplay_active = true
	voting_ui.visible = false
	timer_label.visible = true
	voting_timer.stop()
	game_timer.start(t)
	for child in bodies_container.get_children():
		child.queue_free()
	
	_transition_music(game_ost_player, voting_ost_player, 2.0)

@rpc("call_local", "reliable")
func enable_reports():
	can_report = true

func _on_game_timer_ended():
	if multiplayer.is_server():
		current_votes.clear()
		rpc("start_voting_phase")

func trigger_emergency_meeting(reporter_id: int):
	if not multiplayer.is_server(): return
	if not can_report: return
	
	game_timer.stop()
	current_votes.clear()
	
	rpc("start_report_sequence", reporter_id)

@rpc("call_local", "reliable")
func start_report_sequence(reporter_id: int):
	NetworkHandler.is_gameplay_active = false
	is_voting_phase = false
	is_intermission_phase = false
	
	var reporter_name = "Unknown"
	if NetworkHandler.players.has(reporter_id):
		reporter_name = NetworkHandler.players[reporter_id]["name"]
	
	if report_announce_label:
		report_announce_label.text = "%s HAS REPORTED A CORPSE" % reporter_name
		report_announce_label.modulate = Color.RED
		report_announce_label.visible = true
		
	if multiplayer.is_server():
		await get_tree().create_timer(3.0).timeout
		rpc("start_voting_phase")

@rpc("call_local", "reliable")
func start_voting_phase():
	if report_announce_label: report_announce_label.visible = false
	
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
	
	_transition_music(voting_ost_player, game_ost_player, 1.5)
	
	if NetworkHandler.is_player_dead(multiplayer.get_unique_id()):
		voting_ui.visible = false
		return

	voting_ui.setup_voting(NetworkHandler.players)
	voting_ui.visible = true

@rpc("call_local", "reliable")
func sync_voting_timer(t: float):
	is_voting_phase = true
	is_intermission_phase = false
	NetworkHandler.is_gameplay_active = false
	voting_timer.start(t)
	_transition_music(voting_ost_player, game_ost_player, 1.5)

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
		
		# On élimine le joueur
		NetworkHandler.eliminate_player_by_vote(elim)
		
		# IMPORTANT : On attend un peu pour que la condition de victoire dans eliminate_player_by_vote
		# ait le temps de se propager et d'afficher l'écran de fin SI la partie est finie.
		await get_tree().process_frame
		await get_tree().process_frame
		
		# SI LE JEU EST FINI (Game Over UI visible), ON ARRÊTE TOUT, ON NE LANCE PAS L'INTERMISSION
		if game_over_ui.visible:
			return 
		
		rpc("rpc_voting_completed", elim, false, p_name, p_role)
	else:
		rpc("rpc_voting_completed", -1, true, "", "")
	
	# On ne lance l'intermission que si le jeu n'est pas fini
	rpc("start_intermission_phase")

@rpc("call_local", "reliable")
func rpc_voting_completed(_elim_id: int, tie: bool, player_name: String, player_role: String):
	# Si le jeu est fini, on n'affiche pas ça pour ne pas cacher l'écran de victoire
	if game_over_ui.visible: return

	voting_ui.visible = false
	is_voting_phase = false
	
	if announcement_label:
		if tie:
			announcement_label.text = "DRAW - NO ONE ELIMINATED"
			announcement_label.modulate = Color.WHITE
		elif _elim_id != -1:
			announcement_label.text = "%s was %s !" % [player_name, player_role]
			if player_role == "werewolf": announcement_label.modulate = Color.RED
			else: announcement_label.modulate = Color.GREEN
		
		announcement_label.visible = true

func _on_game_over(winner_role: String):
	print("UI VICTOIRE ACTIVÉE : ", winner_role)
	
	NetworkHandler.is_gameplay_active = false
	
	# On stoppe tous les timers de jeu
	game_timer.stop()
	voting_timer.stop()
	
	# On coupe les musiques
	game_ost_player.stop()
	voting_ost_player.stop()
	
	# On cache tout le reste
	timer_label.visible = false
	voting_ui.visible = false
	if report_label_ui: report_label_ui.visible = false
	if report_announce_label: report_announce_label.visible = false
	if task_counter_label: task_counter_label.visible = false
	if announcement_label: announcement_label.visible = false
	
	# ON AFFICHE L'ECRAN DE FIN
	game_over_ui.show_victory(winner_role)

func _on_server_disconnected():
	NetworkHandler.is_gameplay_active = false
	set_process(false)
	game_timer.stop()
	voting_timer.stop()
	
	game_ost_player.stop()
	voting_ost_player.stop()
	
	ui_layer.visible = true
	voting_ui.visible = false
	timer_label.visible = false
	if report_label_ui: report_label_ui.visible = false
	if report_announce_label: report_announce_label.visible = false
	if task_counter_label: task_counter_label.visible = false
	
	game_over_ui.show_disconnect()

func _on_go_back_to_menu():
	NetworkHandler.stop_network()
	get_tree().change_scene_to_file("res://main_menu.tscn")

# ... (Reste du code : Spawn cadavres, Handshake...) ...
# (Assure-toi de garder les fonctions spawn_corpse_on_all, etc.)

@rpc("call_local", "reliable")
func spawn_corpse_on_all(player_id: int, pos: Vector2, color: Color, is_flipped: bool):
	var corpse = AnimatedSprite2D.new()
	corpse.name = "Corpse_%d" % player_id
	corpse.sprite_frames = player_sprite_frames
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

@rpc("any_peer", "call_local", "reliable")
func client_ready_for_game():
	if not multiplayer.is_server(): return
	var sid = multiplayer.get_remote_sender_id()
	_handle_new_player_ready(sid)

func _handle_new_player_ready(new_id: int):
	var start_pos = _get_free_spawn_point()
	_spawn_for_peer(new_id, start_pos)
	
	if new_id != 1:
		for player in players_root.get_children():
			var split = player.name.split("_")
			if split.size() > 1:
				var pid = split[1].to_int()
				if pid != new_id:
					spawn_player_on_all.rpc_id(new_id, pid, player.global_position)
		
		if is_intermission_phase:
			rpc_id(new_id, "start_intermission_phase")
		elif is_voting_phase:
			rpc_id(new_id, "start_voting_phase")
			rpc_id(new_id, "sync_voting_timer", voting_timer.time_left)
		else:
			rpc_id(new_id, "sync_game_timer", game_timer.time_left)

func _on_player_connected(_id: int): pass 

func _on_player_disconnected(id: int):
	if multiplayer.is_server():
		rpc("despawn_player_on_all", id)
		if current_votes.has(id):
			current_votes.erase(id)

func _spawn_for_peer(id: int, pos: Vector2):
	rpc("spawn_player_on_all", id, pos)

@rpc("reliable", "call_local")
func spawn_player_on_all(id: int, spawn_pos: Vector2):
	var pname = "Player_%d" % id
	if players_root.has_node(pname): return
	
	var p = PlayerScene.instantiate()
	p.name = pname
	p.set_multiplayer_authority(id)
	p.global_position = spawn_pos
	players_root.add_child(p)

@rpc("reliable", "call_local")
func despawn_player_on_all(id: int):
	var p = players_root.get_node_or_null("Player_%d" % id)
	if p: p.queue_free()
