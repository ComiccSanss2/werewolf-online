extends Node2D 

@export var chest_tile_id: int = 10
@export var radius: float = 18.0
@export var vertical_offset: float = -32.0

var chest_states: Dictionary = {} # {Vector2(x, y): bool(is_open)} 

# {Vector2(chest_pos): int(player_id)} 
# ID 0 = Libre. ID > 0 = Occupé par cet ID joueur.
var chest_occupancy: Dictionary = {}

@onready var tilemap: TileMap = $TileMap 
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var chest_container: Node = $Chests 


func _ready() -> void:
	if tilemap == null:
		push_error("ERRORE: Nodo TileMap non trovato come figlio di TileMap_Interactions!")
		return
	if synchronizer == null:
		push_error("ERRORE: Nodo MultiplayerSynchronizer non trovato!")
		return

	synchronizer.set_multiplayer_authority(1)
	
	_generate() 
		

func _generate() -> void:
	# executé par tous les peers
	for cell in tilemap.get_used_cells(1): 
		if tilemap.get_cell_source_id(1, cell) != chest_tile_id:
			continue
			
		var pos := tilemap.map_to_local(cell)
		pos.y += vertical_offset
		
		# créé l'objet area2D
		var a := Area2D.new()
		a.position = pos
		a.set_meta("chest", true)
		
		a.name = "Chest_" + str(cell.x) + "_" + str(cell.y)
		
		var cs := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = radius
		cs.shape = circ
		a.add_child(cs)
		
		chest_container.add_child(a)
		
		if get_tree().get_multiplayer().is_server():
			chest_states[pos] = false 
			chest_occupancy[pos] = 0 


# ----------------------------------------------------------------------
# --- OCCUPANCY METHODS (Appelés par NetworkHandler sur l'Host) ---
# ----------------------------------------------------------------------

func is_chest_free(chest_position: Vector2) -> bool:
	# Trouve la vraie clé position (pour gérer l'imprécision du float)
	var key = _find_chest_key(chest_position)
	
	# Vérifie si la position est libre (ID 0)
	# Si la clé n'existe pas, default à 1 (occupé) par sécurité.
	return chest_occupancy.get(key, 1) == 0 

func set_chest_occupant(chest_position: Vector2, player_id: int) -> void:
	var key = _find_chest_key(chest_position)
	if key != Vector2.ZERO:
		chest_occupancy[key] = player_id

func clear_chest_occupant(player_id: int) -> void:
	# Cherche le coffre occupé par cet ID joueur et le libère
	for pos in chest_occupancy.keys():
		if chest_occupancy[pos] == player_id:
			chest_occupancy[pos] = 0 # Marque comme libre
			return

# Fonction Helper pour gérer l'imprécision des Vector2 en tant que clés
func _find_chest_key(target_pos: Vector2) -> Vector2:
	for key in chest_states.keys(): # chest_states contient toutes les positions valides
		if key.is_equal_approx(target_pos):
			return key
	return Vector2.ZERO # Non trouvé

# ----------------------------------------------------------------------
# --- RPC ---
# ----------------------------------------------------------------------

@rpc("reliable", "authority", "call_local")
func request_open_chest(chest_position: Vector2):
	
	if not get_tree().get_multiplayer().is_server(): return 
	
	if not chest_states.has(chest_position) or chest_states[chest_position] == true:
		return
		
	# met a jour l'etat
	chest_states[chest_position] = true 
	
	# envoi rpc pour le visuel
	rpc("sync_visual_open_chest", chest_position)


# --- RPC: syncro visuel appelé par host et clients ---

@rpc("reliable", "call_local")
func sync_visual_open_chest(chest_position: Vector2):
	# executé sur tous les peers (host et client)
	
	for chest_area in chest_container.get_children():
		if chest_area is Area2D and chest_area.position.is_equal_approx(chest_position):
			print("Chest open: ", chest_position)
			return
