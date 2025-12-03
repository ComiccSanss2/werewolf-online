extends CharacterBody2D

@export var speed: float = 150.0
var is_in_chest := false
var move_dir := Vector2.ZERO

var last_move_dir: Vector2 = Vector2.DOWN 
var is_hidden: bool = false 

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel
@onready var camera: Camera2D = $Camera2D
@onready var chest_area: Area2D = $ChestDetector
@onready var chest_manager: Node = $"../../TileMap_Interactions" 
@onready var collision_shape: CollisionShape2D = $CollisionShape2D 

func _enter_tree() -> void:
	pass

func _ready() -> void:
	# FIX: Evita l'errore all'avvio se la rete non è ancora attiva
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		set_process_mode(PROCESS_MODE_DISABLED)
		return
		
	camera.enabled = is_multiplayer_authority()
	
	_connect_chest_signals()
	_update_name()
	NetworkHandler.lobby_players_updated.connect(_update_name)

func _connect_chest_signals() -> void:
	chest_area.area_entered.connect(_on_area_entered, 4)
	chest_area.area_exited.connect(_on_area_exited, 4)

func _update_name() -> void:
	if name_label:
		var id := get_multiplayer_authority()
		var player_data = NetworkHandler.players.get(id)
		if player_data and player_data.has("name"):
			name_label.text = player_data["name"]
		else:
			name_label.text = "Player %s" % id


func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return

	# 1. GESTIONE INTERAZIONE (Nascondi/Rivela/Apri cassa)
	if Input.is_action_just_pressed("ui_accept"):
		_try_hide_or_open_chest()

	# 2. BLOCCO TOTALE se il giocatore è nascosto
	if is_hidden:
		velocity = Vector2.ZERO
		move_and_slide() 
		return 
	
	# 3. CALCOLO INPUT MOVIMENTO
	var iv = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)

	move_dir = iv.normalized()
	
	if move_dir != Vector2.ZERO:
		last_move_dir = move_dir

	# 4. LOGICA DI BLOCCO/MOVIMENTO
	if is_in_chest and move_dir == Vector2.ZERO:
		velocity = Vector2.ZERO
	else:
		velocity = move_dir * speed
		
	move_and_slide()

	rpc("_net_state", global_position, move_dir, last_move_dir)
	_update_animation()

# --- LOGICA NASCONDI/RIVELA/APRI (FLUSSO AL SINGLETON) ---

func _try_hide_or_open_chest():
	if not is_multiplayer_authority(): return

	# 1. Se siamo nascosti, chiediamo di rivelarci (uscire dalla cassa)
	if is_hidden:
		NetworkHandler.rpc_id(1, "request_player_hide_state", false) 
		return

	# 2. Cerchiamo una cassa vicina per nasconderci o aprirla
	var overlapping_areas = chest_area.get_overlapping_areas()
	
	# DEBUG: Controlla se il Client rileva la cassa
	print("Client (ID:", get_multiplayer_authority(), ") - Input SPACE premuto. Aree rilevate:", overlapping_areas.size())
	

	for area in overlapping_areas:
		if area.has_meta("chest"):
			
			# Nascondi (RPC inviato al NetworkHandler per la sincronizzazione)
			NetworkHandler.rpc_id(1, "request_player_hide_state", true) 
			return
			
			# Logica per l'apertura della cassa (se la vuoi riattivare con un altro input)
			# var chest_pos = area.position
			# if chest_manager:
			#     chest_manager.rpc_id(1, "request_open_chest", chest_pos)
			
			# return 

# --- RPC DI SINCRONIZZAZIONE VISIVA (Ricevuto dal NetworkHandler) ---

@rpc("any_peer", "call_local", "unreliable")
func sync_player_visual_state(new_state: bool):
	is_hidden = new_state
	
	anim.visible = not new_state
	name_label.visible = not new_state
	collision_shape.disabled = new_state
	
	if new_state:
		anim.stop()
	else:
		_update_animation()


# --- RPC E ANIMAZIONE STANDARD ---

@rpc("any_peer", "call_local", "unreliable")
func _net_state(pos: Vector2, dir: Vector2, last_dir: Vector2) -> void:
	if is_multiplayer_authority(): return
	global_position = pos
	move_dir = dir
	last_move_dir = last_dir
	
	if not is_hidden: 
		_update_animation()

func _update_animation() -> void:
	var current_dir = move_dir
	
	if current_dir == Vector2.ZERO:
		current_dir = last_move_dir
		
		if current_dir.y > 0: anim.play("idle-down")
		elif current_dir.y < 0: anim.play("idle-up")
		else: anim.play("idle-left-right")
		
		anim.flip_h = current_dir.x < 0
		return
	
	# Animazioni di corsa
	if current_dir.y > 0: anim.play("run-down")
	elif current_dir.y < 0: anim.play("run-up")
	else: anim.play("run-left-right")
	anim.flip_h = current_dir.x < 0

# --- SEGNALI AREA ---

func _on_area_entered(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		is_in_chest = true

func _on_area_exited(a: Area2D) -> void:
	if is_multiplayer_authority() and a.has_meta("chest"):
		is_in_chest = false
