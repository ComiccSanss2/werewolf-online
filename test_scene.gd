 extends Node2D
 
 var PlayerScene = preload("res://player.tscn")
 
+@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
+@onready var players_root: Node = $Players
+
 
 func _ready():
 	var mp = get_tree().get_multiplayer()
 
 	# connecter signaux réseau
 	mp.peer_connected.connect(_on_player_connected)
 	mp.peer_disconnected.connect(_on_player_disconnected)
 
-	# SPWAN DU PLAYER LOCAL (host ou client)
-	spawn_player(mp.get_unique_id())
+	spawner.spawn_function = Callable(self, "_spawn_player")
+	spawner.despawn_function = Callable(self, "_despawn_player")
+	spawner.spawn_path = NodePath("Players")
 
-	# Spawn des joueurs déjà connectés (si host)
-	for peer_id in mp.get_peers():
-		if peer_id != mp.get_unique_id():
-			spawn_player(peer_id)
+	if mp.is_server():
+		_spawn_for_peer(mp.get_unique_id())
 
+		for peer_id in mp.get_peers():
+			_spawn_for_peer(peer_id)
 
 
 #############################################################
 #                     PLAYER CONNECTÉ
 #############################################################
 
 func _on_player_connected(peer_id):
 	var mp = get_tree().get_multiplayer()
-	var local_id = mp.get_unique_id()
-
-	if peer_id == local_id:
-		print("IGNORED self connect:", peer_id)
-		return
-
-	if has_node(str(peer_id)):
-		print("Player already exists:", peer_id)
-		return
-
-	print("CONNECTED:", peer_id)
-	spawn_player(peer_id)
 
+	if mp.is_server():
+		_spawn_for_peer(peer_id)
 
 
 #############################################################
 #                     PLAYER DÉCONNECTÉ
 #############################################################
 
 func _on_player_disconnected(peer_id):
-	print("DISCONNECTED:", peer_id)
+	var mp = get_tree().get_multiplayer()
 
-	if has_node(str(peer_id)):
-		get_node(str(peer_id)).queue_free()
+	var player := players_root.get_node_or_null(str(peer_id))
 
+	if player and mp.is_server():
+		spawner.despawn(player)
 
 
 #############################################################
 #                  SPAWN SYSTEM (FIXÉ)
 #############################################################
 
-func spawn_player(peer_id):
+func _spawn_for_peer(peer_id: int):
+	spawner.spawn({"peer_id": peer_id})
+
+
+func _spawn_player(data):
+	var peer_id: int = data.get("peer_id", 0)
 	print("SPAWN PLAYER:", peer_id)
 
 	var p = PlayerScene.instantiate()
 	p.name = str(peer_id)
 
-	# Récupérer le multiplayer
-	var mp = get_tree().get_multiplayer()
-	var local_id = mp.get_unique_id()
-
-	# FIX HOST/CLIENT : appliquer autorité correcte
-	# Le player dont le nom == peer_id = l’autorité du peer_id
 	p.set_multiplayer_authority(peer_id)
 
-	# DEBUG ESSENTIEL : montrez quelle instance est locale
-	if peer_id == local_id:
-		print("[AUTHORITY OK] This Player is LOCAL for peer:", peer_id)
-	else:
-		print("[REMOTE] This Player belongs to peer:", peer_id)
-
-	# Ajouter au monde
-	add_child(p)
-
-	# Spawnpoint aléatoire
 	var spawns = $SpawnPoints.get_children()
-	var spawn = spawns[randi() % spawns.size()]
-	p.global_position = spawn.global_position
+	if spawns.size() > 0:
+		var spawn = spawns[randi() % spawns.size()]
+		p.global_position = spawn.global_position
 
-	# Assigner le pseudo
 	if p.has_node("NameLabel"):
 		p.get_node("NameLabel").text = Network.player_names.get(peer_id, "Player")
 
-	print("SET AUTHORITY:", peer_id, "SPAWN:", spawn.name)
+	players_root.add_child(p)
+
+	return p
+
+
+func _despawn_player(node: Node):
+	if node:
+		node.queue_free()
 
)
