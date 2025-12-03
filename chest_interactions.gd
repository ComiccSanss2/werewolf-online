extends Node2D 

@export var chest_tile_id: int = 10
@export var radius: float = 18.0
@export var vertical_offset: float = -32.0

# Stato: Usiamo la posizione Vector2 come chiave
var chest_states: Dictionary = {} # {Vector2(x, y): bool(is_open)} 

# Riferimenti ai nodi figli
@onready var tilemap: TileMap = $TileMap 
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var chest_container: Node = $Chests 


func _ready() -> void:
	# Controlli di sicurezza
	if tilemap == null:
		push_error("ERRORE: Nodo TileMap non trovato come figlio di TileMap_Interactions!")
		return
	if synchronizer == null:
		push_error("ERRORE: Nodo MultiplayerSynchronizer non trovato!")
		return

	# L'Host (peer ID 1) ha l'autorità sulla sincronizzazione degli stati
	synchronizer.set_multiplayer_authority(1)
	
	# 🛑 CORREZIONE: TUTTI i peer generano i rilevatori (Area2D) localmente
	_generate() 
		

func _generate() -> void:
	# Eseguito da tutti i peer
	for cell in tilemap.get_used_cells(1): 
		if tilemap.get_cell_source_id(1, cell) != chest_tile_id:
			continue
			
		var pos := tilemap.map_to_local(cell)
		pos.y += vertical_offset
		
		# 1. Crea l'oggetto detector (Area2D)
		var a := Area2D.new()
		a.position = pos
		a.set_meta("chest", true)
		
		a.name = "Chest_" + str(cell.x) + "_" + str(cell.y)
		
		# NOTA: Layer/Mask devono essere configurati manualmente in Godot per TileMap e Player Detector
		
		# Configurazione CollisionShape
		var cs := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = radius
		cs.shape = circ
		a.add_child(cs)
		
		# Aggiungi al container Chests
		chest_container.add_child(a)
		
		# 2. Solo l'Host (ID 1) inizializza lo stato nel dizionario di sincronizzazione
		if get_tree().get_multiplayer().is_server():
			chest_states[pos] = false 


# ----------------------------------------------------------------------
# --- RPC e LOGICA (Solo l'Host gestisce l'apertura) ---
# ----------------------------------------------------------------------

@rpc("reliable", "authority", "call_local")
func request_open_chest(chest_position: Vector2):
	# Eseguito sul Server (Host)
	
	if not get_tree().get_multiplayer().is_server(): return 
	
	if not chest_states.has(chest_position) or chest_states[chest_position] == true:
		return
		
	# 1. Aggiorna lo stato (sincronizzato tramite MultiplayerSynchronizer)
	chest_states[chest_position] = true 
	
	# 2. Invia l'RPC per aggiornare gli effetti visivi
	rpc("sync_visual_open_chest", chest_position)


# --- RPC: Sincronizzazione Visiva (Chiamata dall'Host a tutti i Client) ---

@rpc("reliable", "call_local")
func sync_visual_open_chest(chest_position: Vector2):
	# Eseguito su tutti i peer (Host e Client)
	
	# LOGICA VISIVA: Trova la cassa in base alla posizione
	for chest_area in chest_container.get_children():
		if chest_area is Area2D and chest_area.position.is_equal_approx(chest_position):
			# Aggiungi qui la logica per cambiare lo sprite/animazione
			print("Cassa aperta a: ", chest_position)
			return
