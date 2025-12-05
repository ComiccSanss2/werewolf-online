extends Area2D

@export_enum("rock", "water") var task_type: String = "rock"
@export var task_duration: float = 2.0

func _ready():
	set_meta("task", true)
	# DEBUG 1 : Vérifier que la zone existe bien
	print("[TASK_ZONE] Zone créée : ", self.name, " | Type : ", task_type, " | Pos : ", global_position)
