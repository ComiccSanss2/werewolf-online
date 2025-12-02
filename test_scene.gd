extends Node2D

var PlayerScene = preload("res://player.tscn")

@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var players_root: Node = $Players


func _ready():
    var mp = get_tree().get_multiplayer()

    # connecter signaux réseau
    mp.peer_connected.connect(_on_player_connected)
    mp.peer_disconnected.connect(_on_player_disconnected)

    spawner.spawn_function = Callable(self, "_spawn_player")
    spawner.despawn_function = Callable(self, "_despawn_player")
    spawner.spawn_path = NodePath("Players")

    if mp.is_server():
        _spawn_for_peer(mp.get_unique_id())

        for peer_id in mp.get_peers():
            _spawn_for_peer(peer_id)


#############################################################
#                     PLAYER CONNECTÉ
#############################################################

func _on_player_connected(peer_id):
    var mp = get_tree().get_multiplayer()

    if mp.is_server():
        _spawn_for_peer(peer_id)


#############################################################
#                     PLAYER DÉCONNECTÉ
#############################################################

func _on_player_disconnected(peer_id):
    var mp = get_tree().get_multiplayer()

    var player := players_root.get_node_or_null(str(peer_id))

    if player and mp.is_server():
        spawner.despawn(player)


#############################################################
#                  SPAWN SYSTEM (FIXÉ)
#############################################################

func _spawn_for_peer(peer_id: int):
    spawner.spawn({"peer_id": peer_id})


func _spawn_player(data):
    var peer_id: int = data.get("peer_id", 0)
    print("SPAWN PLAYER:", peer_id)

    var p = PlayerScene.instantiate()
    p.name = str(peer_id)

    p.set_multiplayer_authority(peer_id)

    var spawns = $SpawnPoints.get_children()
    if spawns.size() > 0:
        var spawn = spawns[randi() % spawns.size()]
        p.global_position = spawn.global_position

    if p.has_node("NameLabel"):
        p.get_node("NameLabel").text = Network.player_names.get(peer_id, "Player")

    players_root.add_child(p)

    return p


func _despawn_player(node: Node):
    if node:
        node.queue_free()
