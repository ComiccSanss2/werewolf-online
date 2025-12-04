extends Node2D

# Scène principale du jeu - Gère les joueurs, le timer, les votes et les phases

# Scène à instancier
var PlayerScene = preload("res://player.tscn")
var player_sprite_frames = preload("res://player_frames.tres")

# Références aux nœuds
@onready var players_root = $Players
@onready var spawn_points = $SpawnPoints.get_children()
@onready var bodies_container = $DeadBodies

# UI et timers
@onready var game_timer: Timer = $GameTimer
@onready var voting_timer: Timer = $VotingTimer
@onready var ui_layer: CanvasLayer = $UI_Layer
@onready var timer_label: Label = $UI_Layer/TimerLabel
@onready var voting_ui: Control = $UI_Layer/VotingScreen
@onready var game_over_ui: Control = $UI_Layer/GameOverScreen

# Constantes de durée
const GAME_DURATION = 180.0  # 3 minutes
const VOTE_DURATION = 60.0   # 1 minute

# Variables de jeu
var current_votes: Dictionary = {}
var is_voting_phase: bool = false

# ========== Initialisation ==========

func _ready() -> void:
	self.name = "TestScene"
	print("--- TEST SCENE LOADED ---")
	
	var mp = get_tree().get_multiplayer()
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)
	mp.server_disconnected.connect(_on_server_disconnected)
	
	# Connexion au signal game_over
	if not NetworkHandler.game_over.is_connected(_on_game_over):
		NetworkHandler.game_over.connect(_on_game_over)
	
	# Configuration de l'UI
	voting_ui.visible = false
	game_over_ui.visible = false
	timer_label.visible = true
	
	if voting_ui.has_signal("vote_cast"):
		if not voting_ui.vote_cast.is_connected(_on_local_player_voted):
			voting_ui.vote_cast.connect(_on_local_player_voted)
	
	if game_over_ui.has_signal("go_to_menu"):
		game_over_ui.go_to_menu.connect(_on_go_back_to_menu)
	
	# Configuration des timers (serveur uniquement)
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
		rpc_id(1, "client_ready_for_game")

# ========== Boucle principale et timer ==========

func _process(_delta: float) -> void:
	var t = 0.0
	var col = Color.WHITE
	
	if is_voting_phase:
		t = voting_timer.time_left
		col = Color.YELLOW
		timer_label.text = "VOTE: %02d" % int(t)
	else:
		if not game_timer.is_stopped():
			t = game_timer.time_left
			timer_label.text = "%02d:%02d" % [floor(t/60), int(t)%60]
			if t < 10: col = Color.RED
	
	timer_label.modulate = col

# ========== Gestion des timers ==========

# Démarre le timer de jeu
func start_game_timer():
	for child in bodies_container.get_children():
		child.queue_free()
	is_voting_phase = false
	game_timer.start(GAME_DURATION)
	rpc("sync_game_timer", GAME_DURATION)

# RPC: Synchronise le timer de jeu
@rpc("call_local", "reliable")
func sync_game_timer(t: float):
	is_voting_phase = false
	voting_ui.visible = false
	timer_label.visible = true
	voting_timer.stop()
	game_timer.start(t)
	for child in bodies_container.get_children():
		child.queue_free()

# Timer de jeu terminé
func _on_game_timer_ended():
	if multiplayer.is_server():
		current_votes.clear()
		rpc("start_voting_phase")

# ========== Phase de vote ==========

# RPC: Démarre la phase de vote
@rpc("call_local", "reliable")
func start_voting_phase():
	is_voting_phase = true
	timer_label.visible = true
	if multiplayer.is_server():
		voting_timer.start(VOTE_DURATION)
		rpc("sync_voting_timer", VOTE_DURATION)
	
	# Les morts ne votent pas
	if NetworkHandler.is_player_dead(multiplayer.get_unique_id()):
		voting_ui.visible = false
		return

	# Prépare la liste des joueurs vivants
	var alive = {}
	for id in NetworkHandler.players:
		if not NetworkHandler.is_player_dead(id):
			alive[id] = NetworkHandler.players[id]
	voting_ui.setup_voting(alive)
	voting_ui.visible = true

# RPC: Synchronise le timer de vote
@rpc("call_local", "reliable")
func sync_voting_timer(t: float):
	is_voting_phase = true
	voting_timer.start(t)

# Joueur local a voté
func _on_local_player_voted(target_id):
	rpc_id(1, "submit_vote", target_id)

# RPC: Soumet un vote au serveur
@rpc("any_peer", "call_local", "reliable")
func submit_vote(target_id):
	if not multiplayer.is_server(): return
	var vid = multiplayer.get_remote_sender_id()
	if NetworkHandler.is_player_dead(vid): return
	current_votes[vid] = target_id
	# Si tout le monde a voté, accélère le timer
	if current_votes.size() >= NetworkHandler.get_alive_players().size():
		if voting_timer.time_left > 10.0:
			voting_timer.start(10.0)
			rpc("sync_voting_timer", 10.0)

# Timer de vote terminé
func _on_voting_timer_ended():
	if multiplayer.is_server():
		_resolve_voting_results()

# Résout les résultats du vote
func _resolve_voting_results():
	var counts = {}
	for t in current_votes.values(): counts[t] = counts.get(t, 0) + 1
	var max_v = 0
	var elim = -1
	var tie = false
	
	for t in counts:
		if counts[t] > max_v:
			max_v = counts[t]
			elim = t
			tie = false
		elif counts[t] == max_v:
			tie = true
	
	# Élimine le joueur si pas d'égalité
	if elim != -1 and not tie:
		NetworkHandler.request_kill_player(elim)
		rpc("rpc_voting_completed", elim, false)
	else:
		rpc("rpc_voting_completed", -1, true)
	
	# Attend 5 secondes avant de relancer le jeu
	await get_tree().create_timer(5.0).timeout
	if game_over_ui.visible == false:
		start_game_timer()

# RPC: Vote terminé
@rpc("call_local", "reliable")
func rpc_voting_completed(elim_id: int, tie: bool):
	voting_ui.visible = false
	is_voting_phase = false

# ========== Gestion fin de partie ==========

# Victoire d'une équipe
func _on_game_over(winner_role: String):
	print("UI VICTOIRE ACTIVÉE : ", winner_role)
	game_timer.stop()
	voting_timer.stop()
	timer_label.visible = false
	voting_ui.visible = false
	game_over_ui.show_victory(winner_role)

# Serveur déconnecté
func _on_server_disconnected():
	print("ALERTE : LE HOST A DISPARU")
	set_process(false)
	game_timer.stop()
	voting_timer.stop()
	ui_layer.visible = true
	voting_ui.visible = false
	timer_label.visible = false
	game_over_ui.show_disconnect()

# Retour au menu
func _on_go_back_to_menu():
	NetworkHandler.stop_network()
	get_tree().change_scene_to_file("res://main_menu.tscn")

# ========== Spawn des cadavres ==========

# RPC: Spawn un cadavre sur tous les clients
@rpc("call_local", "reliable")
func spawn_corpse_on_all(pos: Vector2, color: Color, is_flipped: bool):
	print("SPAWN CORPS à ", pos)
	var corpse = AnimatedSprite2D.new()
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

# ========== Handshake et synchronisation ==========

# RPC: Client prêt à jouer
@rpc("any_peer", "call_local", "reliable")
func client_ready_for_game():
	if not multiplayer.is_server(): return
	var sid = multiplayer.get_remote_sender_id()
	print("SERVER: Client ", sid, " est prêt.")
	_handle_new_player_ready(sid)

# Gère l'arrivée d'un nouveau joueur
func _handle_new_player_ready(new_id: int):
	_spawn_for_peer(new_id)
	if new_id != 1:
		# Envoie les joueurs existants au nouveau client
		for pid in multiplayer.get_peers():
			if pid != new_id: spawn_player_on_all.rpc_id(new_id, pid)
		spawn_player_on_all.rpc_id(new_id, 1)  # Envoie l'host
		
		# Synchronise l'état du jeu
		if is_voting_phase:
			rpc_id(new_id, "start_voting_phase")
			rpc_id(new_id, "sync_voting_timer", voting_timer.time_left)
		else:
			rpc_id(new_id, "sync_game_timer", game_timer.time_left)

# ========== Gestion des joueurs (spawn/despawn) ==========

# Signal: Joueur connecté (non utilisé, handshake manuel)
func _on_player_connected(id: int): pass

# Signal: Joueur déconnecté
func _on_player_disconnected(id: int):
	print("SIGNAL: Peer disconnected ", id)
	
	if multiplayer.is_server():
		rpc("despawn_player_on_all", id)
		if current_votes.has(id):
			current_votes.erase(id)

# Demande le spawn d'un joueur (serveur uniquement)
func _spawn_for_peer(id: int):
	rpc("spawn_player_on_all", id)

# RPC: Spawn un joueur sur tous les clients
@rpc("reliable", "call_local")
func spawn_player_on_all(id: int):
	var pname = "Player_%d" % id
	if players_root.has_node(pname): return
	var p = PlayerScene.instantiate()
	p.name = pname
	p.set_multiplayer_authority(id)
	p.global_position = spawn_points[randi() % spawn_points.size()].global_position
	players_root.add_child(p)

# RPC: Détruit un joueur sur tous les clients
@rpc("reliable", "call_local")
func despawn_player_on_all(id: int):
	var p = players_root.get_node_or_null("Player_%d" % id)
	if p: p.queue_free()
