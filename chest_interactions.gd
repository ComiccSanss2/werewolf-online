extends Node2D

@export var tilemap: TileMap
@export var chest_tile_id: int = 10
@export var radius: float = 12.0
@export var vertical_offset: float = -32.0      

func _ready():
	generate_zones()

func generate_zones():
	var used = tilemap.get_used_cells(1)

	for cell in used:
		var tile = tilemap.get_cell_source_id(1, cell)

		if tile == chest_tile_id:

			# position base = centre du tile
			var world = tilemap.map_to_local(cell) + tilemap.tile_set.tile_size * 0.0

			# ajustement vertical
			world.y += vertical_offset   # <-- ICI

			var area := Area2D.new()
			area.position = world

			area.name = "ChestArea_%s".format(cell)
			area.set_meta("chest", true)
			area.set_meta("occupied", false)

			area.collision_layer = 1
			area.collision_mask = 1

			var col := CollisionShape2D.new()
			var circ := CircleShape2D.new()
			circ.radius = radius
			col.shape = circ
			area.add_child(col)

			add_child(area)
