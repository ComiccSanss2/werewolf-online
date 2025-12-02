extends Node2D

var PlayerScene = preload("res://scenes/characters/player.tscn")


func _ready():
	var mp = get_tree().get_multiplayer()

	# connecter signaux
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)

	# spawn du joueur local
	spawn_player(mp.get_unique_id())

	# spawn des joueurs déjà connectés
	for peer_id in mp.get_peers():
		if peer_id != mp.get_unique_id():
			spawn_player(peer_id)


func _on_player_connected(peer_id):
	var mp = get_tree().get_multiplayer()
	var local_id = mp.get_unique_id()

	# Ne pas spawn soi-même
	if peer_id == local_id:
		print("IGNORED self connect:", peer_id)
		return

	# Si déjà spawn → on ignore
	if has_node(str(peer_id)):
		print("Player already exists:", peer_id)
		return

	print("CONNECTED:", peer_id)
	spawn_player(peer_id)


func _on_player_disconnected(peer_id):
	print("DISCONNECTED:", peer_id)

	if has_node(str(peer_id)):
		get_node(str(peer_id)).queue_free()


#####################################
#          SPAWN SYSTEM             #
#####################################

func spawn_player(peer_id):
	print("SPAWN PLAYER:", peer_id)

	var p = PlayerScene.instantiate()
	p.name = str(peer_id)

	# Autorité réseau
	p.set_multiplayer_authority(peer_id)

	# Ajouter au monde
	add_child(p)

	# Spawnpoint aléatoire
	var spawns = $SpawnPoints.get_children()
	var spawn = spawns[randi() % spawns.size()]
	p.global_position = spawn.global_position

	# ASSIGNER LE PSEUDO AU LABEL AU-DESSUS DU JOUEUR
	if p.has_node("NameLabel"):
		p.get_node("NameLabel").text = Network.player_names.get(peer_id, "Player")

	print("SET AUTHORITY:", peer_id, "SPAWN:", spawn.name)
