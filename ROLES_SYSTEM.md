# 🎭 Système de Rôles - Loup-Garou Online

## 📋 Vue d'ensemble

Le système de rôles permet d'attribuer automatiquement et aléatoirement des rôles aux joueurs quand une partie commence.

## 🏗️ Architecture

```
scripts/roles/
├── role.gd          # Classe de base pour tous les rôles
├── villageois.gd    # Rôle Villageois (équipe village)
└── loup_garou.gd    # Rôle Loup-Garou (équipe loup)

autoload/
├── Network.gd       # Gestion réseau + stockage du rôle local
└── RoleManager.gd   # Attribution et gestion des rôles
```

## 🎮 Rôles disponibles

### 👤 Villageois (Équipe Village)
- **Objectif** : Éliminer tous les loups-garous
- **Pouvoir** : Aucun pouvoir spécial
- **Actions** :
  - 🌞 Jour : Peut voter pour éliminer un suspect
  - 🌙 Nuit : Dort paisiblement

### 🐺 Loup-Garou (Équipe Loup)
- **Objectif** : Éliminer tous les villageois
- **Pouvoir** : Vote pour tuer un villageois chaque nuit
- **Actions** :
  - 🌞 Jour : Peut voter (et faire semblant d'être innocent)
  - 🌙 Nuit : Choisit une victime avec les autres loups

## 📊 Répartition des rôles

Le nombre de loups-garous dépend du nombre de joueurs :

| Joueurs | Loups-Garous | Villageois |
|---------|--------------|------------|
| 3       | 1            | 2          |
| 4-5     | 1            | 3-4        |
| 6-8     | 2            | 4-6        |
| 9-10    | 3            | 6-7        |

## 🔄 Flux du système

1. **Dans le Lobby** (`lobby.gd`)
   - L'hôte clique sur "START"
   - `RoleManager.assign_roles()` est appelé avec la liste des joueurs
   - Les rôles sont distribués aléatoirement
   - Chaque joueur reçoit son rôle via RPC

2. **Dans la partie** (`test_scene.gd`)
   - Le rôle est affiché en haut à gauche
   - Couleur verte = Villageois
   - Couleur rouge = Loup-Garou

## 🛠️ Utilisation du RoleManager

```gdscript
# Attribution des rôles
var player_ids = [1, 2, 3, 4]
var result = RoleManager.assign_roles(player_ids)

# Récupérer le rôle d'un joueur
var role = RoleManager.get_player_role(peer_id)
print(role.role_name)  # "Villageois" ou "Loup-Garou"

# Vérifier si un joueur est un loup
if RoleManager.is_werewolf(peer_id):
    print("C'est un loup !")

# Récupérer tous les loups vivants
var wolves = RoleManager.get_alive_wolves()

# Tuer un joueur
RoleManager.kill_player(peer_id)

# Vérifier les conditions de victoire
var win_check = RoleManager.check_win_condition()
if win_check.game_over:
    print(win_check.message)  # Affiche le message de victoire
```

## ➕ Ajouter un nouveau rôle

1. Créer un nouveau fichier dans `scripts/roles/` (ex: `voyante.gd`)
2. Hériter de la classe `Role`
3. Définir les propriétés dans `_init()`
4. Implémenter `day_action()` et `night_action()`
5. Ajouter le rôle dans `RoleManager._create_role()`

Exemple :

```gdscript
class_name Voyante
extends Role

func _init():
    role_name = "Voyante"
    description = "Chaque nuit, vous pouvez voir le rôle d'un joueur."
    team = "village"
    is_alive = true
    can_vote = true

func night_action() -> Dictionary:
    return {
        "success": true,
        "action": "spy",
        "message": "Choisissez un joueur à espionner...",
        "can_target": true
    }
```

## 🎯 Prochaines étapes

- [ ] Ajouter plus de rôles (Voyante, Sorcière, Chasseur, etc.)
- [ ] Implémenter les phases jour/nuit
- [ ] Système de vote
- [ ] Interface pour les actions de nuit des loups
- [ ] Écran de fin de partie avec statistiques

## 📝 Notes techniques

- Les rôles sont assignés côté serveur uniquement
- Chaque client reçoit uniquement son propre rôle (pas ceux des autres)
- Les rôles sont stockés dans `Network.my_role_*` pour le joueur local
- Le `RoleManager` est un autoload accessible partout

