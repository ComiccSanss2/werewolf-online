# HouseDoor.gd
extends Node2D

func _ready():
	set_meta("door", true)

	var door_area = $DoorArea
	if door_area:
		door_area.set_meta("door", true)
	
