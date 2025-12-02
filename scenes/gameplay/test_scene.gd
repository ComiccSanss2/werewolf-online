extends Node2D

var PlayerScene = preload("res://scenes/characters/player.tscn")

var role_label: Label


func _ready():
	var mp = get_tree().get_multiplayer()

	# Créer l'UI pour afficher le rôle
	_create_role_ui()
	
	# connecter signaux
	mp.peer_connected.connect(_on_player_connected)
	mp.peer_disconnected.connect(_on_player_disconnected)
	
	# Afficher le rôle du joueur local
	_display_role()

	# spawn du joueur local
	spawn_player(mp.get_unique_id())

	# spawn des joueurs déjà connectés
	for peer_id in mp.get_peers():
		if peer_id != mp.get_unique_id():
			spawn_player(peer_id)


func _create_role_ui():
	# Créer un CanvasLayer pour l'UI
	var canvas = CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)
	
	# Créer un panel pour le rôle
	var panel = PanelContainer.new()
	panel.position = Vector2(10, 10)
	canvas.add_child(panel)
	
	# Créer un VBoxContainer
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	# Label pour le nom du rôle
	role_label = Label.new()
	role_label.text = "Chargement..."
	role_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(role_label)
	
	# Label pour la description
	var desc_label = Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = ""
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(desc_label)


func _display_role():
	if Network.my_role_name != "":
		var color = Color.GREEN if Network.my_role_team == "village" else Color.RED
		role_label.text = "🎭 Votre rôle : " + Network.my_role_name
		role_label.add_theme_color_override("font_color", color)
		
		# Afficher la description
		var desc_label = role_label.get_parent().get_node("DescLabel")
		desc_label.text = Network.my_role_description
		
		print("=== VOTRE RÔLE ===")
		print("Nom: %s" % Network.my_role_name)
		print("Équipe: %s" % Network.my_role_team)
		print("Description: %s" % Network.my_role_description)
		print("==================")
	else:
		role_label.text = "Rôle non attribué"


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
