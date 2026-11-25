# SECTOR 09 // BODYCAM

![Godot 4.4](https://img.shields.io/badge/Godot-4.4_Forward%2B-478cbf?logo=godotengine&logoColor=white)
![Linux x86_64](https://img.shields.io/badge/Linux-x86__64_Vulkan-FCC624?logo=linux&logoColor=black)
![License MIT](https://img.shields.io/badge/License-MIT-green)

FPS tactique photoréaliste en vue **Bodycam** (style *Unrecord* / *Bodycam*), conçu pour **Linux (Vulkan / Forward+)** et distribué en **binaire autonome installable sans Godot**.

> **Téléchargement direct Linux (sans Godot requis)** : rendez-vous dans l'onglet [**Releases**](https://github.com/TheShellMaster/sector-09-bodycam-fps/releases/latest) et téléchargez `Sector09-Bodycam-Linux-x86_64.tar.gz`.

## Fonctionnalités de Réalisme

### 1. Rendu Photoréaliste (Godot 4.4 Forward+)
- **Tonemapping AgX Filmic** natif, **SSAO**, **SSIL**, **SSR** (reflets temps réel sur l'asphalte mouillé et les flaques d'eau), **Brouillard Volumétrique** (faisceaux lumineux des lampadaires et de la lampe tactique), **TAA** et option **SDFGI** (illumination globale temps réel) dans le menu `ESC`.
- **Textures PBR procédurales** complètes (*Albedo, Normal, Roughness, Ambient Occlusion*) générées pour le béton, l'asphalte humide à flaques, la brique industrielle, le métal rouillé, les caisses en bois et les sols d'entrepôt huileux.
- **Shader Post-Processing Bodycam (`shaders/bodycam_post.gdshader`)** : distorsion optique grand-angle (fisheye réglable), aberration chromatique radiale, grain CMOS ISO dynamique (plus intense en basse lumière), gouttes de pluie sur la lentille en extérieur, micro-netteté caméra, vignette de blessure et **mode Vision Nocturne IR (`N`)**.
- **Cycle Jour/Nuit & Météo Dynamique** : ciel physique, pluie 3D, mouillage dynamique des surfaces extérieures, éclairs avec tonnerre différé et allumage automatique des lampadaires au crépuscule.

### 2. Physique, Mouvements & Balistique
- **Contrôleur Bodycam à inertie** : accélération/décélération réalistes, balancement organique synchronisé avec les pas et détection de surface au sol (béton, flaques, métal, bois), endurance et rythme cardiaque (**BPM**), accroupissement, et **pencher gauche/droite (`A`/`E`)** avec détection d'obstacle mural.
- **Arme tactique MK-18** : viseur holographique, lampe tactique volumétrique (`F`), laser PEQ-15 raycast réel (`L`), sélecteur Semi/Auto (`X`), culasse mobile, recul caméra + arme, inertie *free-aim* à la hanche, **éjection physique de douilles en laiton (`RigidBody3D`)**, balistique avec chute de gravité, traînée aérodynamique, impacts par matériau et impulsion sur les objets physiques (barils, caisses).
- **Gestion réaliste des chargeurs** : pas de compteur arcade permanent — utilisez `B` pour vérifier le poids estimé du chargeur.

### 3. Immersion Sonore 3D & Interface Diégétique
- Audio 3D spatialisé avec bascule automatique entre bus **Extérieur** et **Intérieur (réverbération d'entrepôt)** selon la présence d'un plafond au-dessus du joueur, plus atténuation de la pluie en intérieur et battements de cœur physiologiques.
- Overlay authentique **AXON BODY 4 // REC** avec horodatage temps réel, zone (`INT`/`EXT`), BPM, statut mission et journal d'événements tactiques.

### 4. Trois Niveaux Tactiques & IA Ennemie
1. **NIV. 01 // SECTOR 09 — Cour & Entrepôt** : cour mouillée sous l'orage, poste de garde, entrepôt industriel sur 2 niveaux, disjoncteur électrique sabotable, 5 hostiles IA.
2. **NIV. 02 // SECTOR 14 — Docks & Conteneurs** : labyrinthe nocturne de conteneurs dans un brouillard dense, projecteurs, bureau de commandement, 7 hostiles IA.
3. **NIV. 03 // SECTOR 21 — Bunker Souterrain** : complexe en béton brutaliste, éclairages d'urgence clignotants, couloirs CQB serrés, 8 hostiles IA.

Les **personnages IA** patrouillent, réagissent à la **lumière** (votre lampe/laser vous trahit dans le noir ; couper le disjoncteur les plonge dans l'obscurité), **entendent** les coups de feu, impacts et sprints, alertent leur escouade par radio, tirent par rafales balistiques et disposent de hitboxes localisées (tête / corps).

## Commandes (AZERTY & QWERTY supportés automatiquement)

| Touche | Action |
| :--- | :--- |
| `Z Q S D` / `W A S D` | Déplacement |
| `Shift` | Sprint tactique |
| `Ctrl` / `C` | Accroupir |
| `Espace` | Sauter |
| `A` / `E` (ou `Q` / `E`) | Se pencher gauche / droite |
| `Clic Gauche` / `Clic Droit` | Tirer / Viser (ADS) |
| `R` / `B` / `X` | Recharger / Vérifier chargeur / Semi-Auto |
| `F` / `L` / `N` | Lampe tactique / Laser PEQ-15 / Vision Nocturne IR |
| `E` ou `V` ou `Entrée` | Interagir (Intel, Disjoncteur électrique, Munitions) |
| `T` | Changer la météo et l'heure |
| `G` / `H` | Point central optionnel / Afficher ou masquer l'aide |
| `ESC` | Menu Pause, Sélection des 3 Niveaux & Réglages Graphiques |

## Lancer ou Partager le Jeu (Linux sans Godot)

- **Version autonome prête à partager (sans Godot)** :
  - Dossier : `dist/Sector09-Linux/`
  - Archive partageable : `dist/Sector09-Bodycam-Linux-x86_64.tar.gz`
  - Lancer directement : `./dist/Sector09-Linux/Sector09.x86_64`
  - Installer dans le système (menu d'applications + commande `sector09`) : `./dist/Sector09-Linux/install.sh`
- **Reconstruire l'archive Linux après modifications** : `./build_linux_release.sh`
- **Lancer depuis les sources avec Godot** : `./play.sh`
