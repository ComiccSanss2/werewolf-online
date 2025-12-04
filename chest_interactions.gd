extends Node2D

# Configuration des coffres
@export var chest_tile_id: int = 10
@export var radius: float = 18.0
@export var vertical_offset: float = -32.0

# États des coffres : {position: bool(is_open)}
var chest_states: Dictionary = {}
# Occupation des coffres : {position: player_id} (0 = libre)
var chest_occupancy: Dictionary = {}

# Références aux nœuds
@onready var tilemap: TileMap = $TileMap
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var chest_container: Node = $Chests

func _ready() -> void:
	if not tilemap or not synchronizer:
		return
	# L'autorité réseau est toujours le serveur (ID 1)
	synchronizer.set_multiplayer_authority(1)
	_generate()

# Génère les zones de détection pour tous les coffres de la carte
func _generate() -> void:
	var mp = get_tree().get_multiplayer()
	var is_server = mp.is_server()
	
	# Parcourir toutes les cellules de la couche 1
	for cell in tilemap.get_used_cells(1):
		if tilemap.get_cell_source_id(1, cell) != chest_tile_id:
			continue

		# Calculer la position du coffre avec l'offset vertical
		var pos = tilemap.map_to_local(cell)
		pos.y += vertical_offset

		# Créer une zone de détection pour le coffre
		var area = Area2D.new()
		area.position = pos
		area.set_meta("chest", true)
		area.name = "Chest_%d_%d" % [cell.x, cell.y]

		# Ajouter une forme de collision circulaire
		var shape = CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = radius
		area.add_child(shape)
		chest_container.add_child(area)

		# Initialiser les états uniquement sur le serveur
		if is_server:
			chest_states[pos] = false
			chest_occupancy[pos] = 0


# Vérifie si un coffre est libre (non occupé)
func is_chest_free(chest_position: Vector2) -> bool:
	return chest_occupancy.get(_find_chest_key(chest_position), 1) == 0

# Assigne un joueur à un coffre
func set_chest_occupant(chest_position: Vector2, player_id: int) -> void:
	var key = _find_chest_key(chest_position)
	if key != Vector2.ZERO:
		chest_occupancy[key] = player_id

# Libère le coffre occupé par un joueur
func clear_chest_occupant(player_id: int) -> void:
	for pos in chest_occupancy:
		if chest_occupancy[pos] == player_id:
			chest_occupancy[pos] = 0
			break

# Trouve la clé de position exacte pour gérer l'imprécision des floats
func _find_chest_key(target_pos: Vector2) -> Vector2:
	for key in chest_states:
		if key.is_equal_approx(target_pos):
			return key
	return Vector2.ZERO

# RPC : Demande d'ouverture d'un coffre (uniquement traité par le serveur)
@rpc("reliable", "authority", "call_local")
func request_open_chest(chest_position: Vector2):
	if not get_tree().get_multiplayer().is_server():
		return
	# Vérifier que le coffre existe et n'est pas déjà ouvert
	if not chest_states.has(chest_position) or chest_states[chest_position]:
		return
	# Marquer le coffre comme ouvert et synchroniser avec tous les clients
	chest_states[chest_position] = true
	rpc("sync_visual_open_chest", chest_position)

# RPC : Synchronise l'état visuel d'un coffre ouvert sur tous les clients
@rpc("reliable", "call_local")
func sync_visual_open_chest(chest_position: Vector2):
	for area in chest_container.get_children():
		if area is Area2D and area.position.is_equal_approx(chest_position):
			print("Chest open: ", chest_position)
			break