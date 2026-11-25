#!/usr/bin/env bash
set -euo pipefail

# Builds a standalone Linux x86_64 release of SECTOR 09 // BODYCAM
# that installs and runs on any 64-bit Linux PC WITHOUT Godot installed!

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$PROJECT_DIR/dist/Sector09-Linux"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/4.4.1.stable"
ARCHIVE_OUT="$PROJECT_DIR/dist/Sector09-Bodycam-Linux-x86_64.tar.gz"

mkdir -p "$DIST_DIR"

# 1. Check/Download official Godot 4.4.1 export templates if missing
if [ ! -f "$TEMPLATES_DIR/linux_release.x86_64" ]; then
    echo "[1/4] Téléchargement des templates d'export officiels Godot 4.4.1..."
    mkdir -p "$TEMPLATES_DIR"
    TPZ_URL="https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz"
    TMP_TPZ="/tmp/godot_4.4.1_templates.tpz"
    curl -L --progress-bar "$TPZ_URL" -o "$TMP_TPZ"
    python3 -c "
import zipfile, os, shutil
with zipfile.ZipFile('$TMP_TPZ') as z:
    for name in z.namelist():
        if name.endswith('linux_release.x86_64') or name.endswith('linux_debug.x86_64') or name.endswith('version.txt'):
            dest = os.path.join('$TEMPLATES_DIR', os.path.basename(name))
            with z.open(name) as src, open(dest, 'wb') as dst:
                shutil.copyfileobj(src, dst)
            os.chmod(dest, 0o755)
"
    rm -f "$TMP_TPZ"
    echo "Templates Linux x86_64 installés dans $TEMPLATES_DIR"
fi

# 2. Import resources headless first
echo "[2/4] Importation des ressources PBR & Audio..."
cd "$PROJECT_DIR"
godot --headless --import --quit

# 3. Export standalone single-file Linux binary (embed_pck=true!)
echo "[3/4] Exportation du binaire autonome Linux x86_64..."
godot --headless --export-release "Linux" "$DIST_DIR/Sector09.x86_64"
chmod +x "$DIST_DIR/Sector09.x86_64"

# 4. Generate standalone installer (install.sh) + uninstaller + README inside dist/Sector09-Linux
cat > "$DIST_DIR/install.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Installe SECTOR 09 // BODYCAM pour l'utilisateur courant (sans besoin de Godot ni sudo)
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/share/sector09-bodycam"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"

echo "Installation de SECTOR 09 // BODYCAM dans $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APP_DIR"
cp -f "$SRC_DIR/Sector09.x86_64" "$INSTALL_DIR/Sector09.x86_64"
chmod +x "$INSTALL_DIR/Sector09.x86_64"

cat > "$BIN_DIR/sector09" << LAUNCHER
#!/usr/bin/env bash
exec "$INSTALL_DIR/Sector09.x86_64" "\$@"
LAUNCHER
chmod +x "$BIN_DIR/sector09"

cat > "$APP_DIR/sector09-bodycam.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=SECTOR 09 // BODYCAM
Comment=FPS tactique photoréaliste en vue Bodycam
Exec=$INSTALL_DIR/Sector09.x86_64
Terminal=false
Categories=Game;ActionGame;Shooter;
DESKTOP

echo "Installation terminée !"
echo "Lancez le jeu depuis votre menu d'applications (« SECTOR 09 // BODYCAM ») ou via : $BIN_DIR/sector09"
EOF
chmod +x "$DIST_DIR/install.sh"

cat > "$DIST_DIR/uninstall.sh" << 'EOF'
#!/usr/bin/env bash
rm -rf "$HOME/.local/share/sector09-bodycam"
rm -f "$HOME/.local/bin/sector09"
rm -f "$HOME/.local/share/applications/sector09-bodycam.desktop"
echo "SECTOR 09 // BODYCAM désinstallé."
EOF
chmod +x "$DIST_DIR/uninstall.sh"

cat > "$DIST_DIR/LISEZMOI.txt" << 'EOF'
SECTOR 09 // BODYCAM — Édition Linux Autonome (x86_64)
=====================================================
Aucun moteur (ni Godot) n'est requis pour jouer !

1) JOUER DIRECTEMENT :
   ./Sector09.x86_64

2) INSTALLER DANS LE SYSTÈME (raccourci menu + commande 'sector09') :
   ./install.sh

3) DÉSINSTALLER :
   ./uninstall.sh

COMMANDES (AZERTY & QWERTY supportés automatiquement) :
- ZQSD / WASD : Déplacer | Shift : Sprint | Ctrl / C : Accroupir
- A / E : Se pencher | Clic Gauche : Tirer | Clic Droit : Viser (ADS)
- R : Recharger | B : Vérifier chargeur | X : Semi / Auto
- F : Lampe tactique | L : Laser PEQ-15 | N : Vision Nocturne IR
- E / V : Interagir (Intel, Disjoncteur électrique, Munitions)
- T : Changer météo / heure | G : Point central | H : Aide | ESC : Menu & Niveaux
EOF

echo "[4/4] Création de l'archive partageable..."
tar -czf "$ARCHIVE_OUT" -C "$PROJECT_DIR/dist" "Sector09-Linux"
echo "SUCCÈS ! Archive prête à partager : $ARCHIVE_OUT"
ls -lh "$DIST_DIR/Sector09.x86_64" "$ARCHIVE_OUT"
