# Contribuer à SECTOR 09 // BODYCAM

Merci de votre intérêt pour **SECTOR 09 // BODYCAM** ! Toutes les contributions sont les bienvenues : nouveaux niveaux, armes, modèles 3D (glTF/Blender), améliorations IA, shaders, sons, traductions ou corrections de bugs.

## Comment contribuer (Pull Request)

1. **Forkez** le dépôt sur GitHub.
2. **Clonez** votre fork :
   ```bash
   git clone https://github.com/<votre-pseudo>/sector-09-bodycam-fps.git
   cd sector-09-bodycam-fps
   ```
3. **Créez une branche** claire pour votre ajout :
   ```bash
   git checkout -b feat/mon-nouveau-niveau
   ```
4. **Testez votre modification** avec **Godot 4.4+** (Forward+) :
   ```bash
   ./play.sh
   # Vérification headless sans erreur :
   godot --headless --quit-after 60
   ```
5. **Régénérez les assets** si vous avez modifié `tools/generate_assets.py` :
   ```bash
   python3 tools/generate_assets.py
   ```
6. **Commitez & poussez**, puis ouvrez une **Pull Request** sur `main`.

## Où ajouter du contenu ?

| Ce que vous voulez ajouter | Fichiers concernés |
| :--- | :--- |
| **Nouveau niveau / carte** | `scripts/world/level_builder.gd` + `LEVEL_NAMES` dans `scripts/core/game_manager.gd` |
| **Nouvelle arme / équipement** | `scripts/weapons/tactical_weapon.gd`, `scripts/weapons/ballistic_projectile.gd` |
| **Comportement IA / ennemis** | `scripts/ai/tactical_ai.gd` |
| **Shader / rendu Bodycam / météo** | `shaders/bodycam_post.gdshader`, `scripts/environment/weather_cycle.gd` |
| **Textures PBR / Audio** | `assets/textures/`, `assets/audio/`, `tools/generate_assets.py` |
| **HUD / Menu / Traductions** | `scripts/ui/bodycam_hud.gd` |

## Conventions
- Gardez le jeu **100 % compatible Linux x86_64 (Vulkan / Forward+)** et exportable en autonome via `./build_linux_release.sh`.
- Évitez de commiter `.godot/` ou `dist/` (déjà ignorés dans `.gitignore`).
- Utilisez des types explicites en GDScript pour éviter les erreurs de compilation headless.
