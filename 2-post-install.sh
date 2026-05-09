#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║         ARCH LINUX POST-INSTALL — Étape 2 (KDE)             ║
# ║   À lancer APRÈS le premier démarrage dans KDE Plasma        ║
# ║   Installe : yay (AUR) · envycontrol · mode GPU hybride      ║
# ╚══════════════════════════════════════════════════════════════╝
# Usage : bash 2-post-install.sh

set -uo pipefail
trap 's=$?; echo -e "\n❌ Erreur ligne $LINENO : $BASH_COMMAND\n"; exit $s' ERR

GREEN='\033[0;32m'; BLUE='\033[0;34m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "\n${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
banner()  { echo -e "\n${BOLD}══ $1 ══${NC}"; }

# ══════════════════════════════════════════════════════════
#  VÉRIFICATIONS
# ══════════════════════════════════════════════════════════
banner "VÉRIFICATIONS"

[[ "$EUID" -ne 0 ]] || { echo "❌ Ne lance pas ce script en root ! Utilise ton compte utilisateur."; exit 1; }

info "Connexion internet..."
ping -c 1 -W 3 archlinux.org &>/dev/null || { echo "❌ Pas de connexion internet !"; exit 1; }
success "Connexion OK"

# ══════════════════════════════════════════════════════════
#  YAY (AUR HELPER — compilé depuis source)
# ══════════════════════════════════════════════════════════
banner "YAY — AUR HELPER (compilé depuis source)"

if command -v yay &>/dev/null; then
    success "yay déjà installé, skip."
else
    info "Clonage et compilation de yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay-build
    cd /tmp/yay-build
    makepkg -si --noconfirm
    cd ~
    rm -rf /tmp/yay-build
    success "yay installé"
fi

# ══════════════════════════════════════════════════════════
#  WATERFOX (depuis le site officiel — tarball)
# ══════════════════════════════════════════════════════════
banner "WATERFOX (tarball officiel)"

if command -v waterfox &>/dev/null; then
    success "Waterfox déjà installé, skip."
else
    info "Récupération de la dernière version via l'API GitHub..."
    LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/BrowserWorks/Waterfox/releases/latest \
        | grep -m1 tag_name | cut -d '"' -f4)
    [[ -z "$LATEST_VERSION" ]] && { echo "❌ Impossible de récupérer la version de Waterfox !"; exit 1; }
    success "Dernière version : $LATEST_VERSION"

    DOWNLOAD_URL="https://cdn.waterfox.com/waterfox/releases/${LATEST_VERSION}/Linux_x86_64/waterfox-${LATEST_VERSION}.tar.bz2"
    TMPDIR=$(mktemp -d)

    info "Téléchargement de $DOWNLOAD_URL..."
    curl -fL --progress-bar -o "$TMPDIR/waterfox.tar.bz2" "$DOWNLOAD_URL"

    info "Extraction dans /opt/..."
    sudo tar -xjf "$TMPDIR/waterfox.tar.bz2" -C /opt/
    rm -rf "$TMPDIR"

    info "Création du symlink..."
    sudo ln -sf /opt/waterfox/waterfox /usr/local/bin/waterfox

    info "Création du raccourci bureau (KDE)..."
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/waterfox.desktop << EOF
[Desktop Entry]
Name=Waterfox
GenericName=Web Browser
Exec=/opt/waterfox/waterfox %u
Icon=/opt/waterfox/browser/chrome/icons/default/default256.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/vnd.mozilla.xul+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF

    success "Waterfox $LATEST_VERSION installé dans /opt/waterfox"
fi

# ══════════════════════════════════════════════════════════
#  ENVYCONTROL (GPU SWITCHING)
# ══════════════════════════════════════════════════════════
banner "ENVYCONTROL"

if command -v envycontrol &>/dev/null; then
    success "envycontrol déjà installé, skip."
else
    info "Installation d'envycontrol depuis l'AUR..."
    yay -S --noconfirm envycontrol
    success "envycontrol installé"
fi

# ══════════════════════════════════════════════════════════
#  MODE GPU HYBRIDE
# ══════════════════════════════════════════════════════════
banner "GPU — MODE HYBRIDE"
info "Configuration du mode Optimus hybride..."
info "(AMD par défaut · NVIDIA à la demande via switcheroo-control)"

sudo envycontrol -s hybrid
success "Mode hybride activé"

info "Mode GPU actuel :"
envycontrol --query


# ══════════════════════════════════════════════════════════
#  GEAR LEVER (GESTIONNAIRE D'APPIMAGE)
# ══════════════════════════════════════════════════════════
banner "GEAR LEVER — GESTIONNAIRE D'APPIMAGE"
if command -v gear-lever &>/dev/null; then
    success "Gear Lever déjà installé, skip."
else
    info "Installation de Gear Lever (AUR)..."
    yay -S --noconfirm gear-lever
    success "Gear Lever installé"
fi

# ══════════════════════════════════════════════════════════
#  ÉMULATEURS & OUTILS DE COMPATIBILITÉ
# ══════════════════════════════════════════════════════════
banner "ÉMULATEURS & COMPATIBILITÉ WINDOWS"

APPDIR="$HOME/Applications"
mkdir -p "$APPDIR"

# ── Fonction de téléchargement AppImage depuis GitHub ────
download_appimage() {
    local repo="$1"
    local pattern="$2"
    local name="$3"
    info "Téléchargement de $name (AppImage)..."
    if [[ -f "$APPDIR/$name" ]]; then
        success "$name déjà présent, skip."
        return
    fi
    local url
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*'"$pattern"'[^"]*"' \
        | grep -v 'zsync\|debug\|symbols' \
        | head -1 \
        | cut -d'"' -f4)
    if [[ -z "$url" ]]; then
        warn "URL introuvable pour $name — passage en mode pacman."
        return 1
    fi
    curl -fsSL --progress-bar -o "$APPDIR/$name" "$url"
    chmod +x "$APPDIR/$name"
    success "$name installé dans $APPDIR/"
}

# ── AppImages — téléchargées depuis GitHub ───────────────
# RetroArch (nightly officiel)
info "Téléchargement de RetroArch (AppImage nightly)..."
if [[ -f "$APPDIR/RetroArch.AppImage" ]]; then
    success "RetroArch déjà présent, skip."
else
    curl -fsSL --progress-bar \
        -o "$APPDIR/RetroArch.AppImage" \
        "https://github.com/hizzlekizzle/RetroArch-AppImage/releases/download/Linux_LTS_Nightlies/RetroArch-Linux-x86_64-Nightly.AppImage"
    chmod +x "$APPDIR/RetroArch.AppImage"
    success "RetroArch AppImage installé"
fi

download_appimage "PCSX2/pcsx2"          "AppImage"   "pcsx2-Qt.AppImage"     || sudo pacman -S --noconfirm pcsx2
download_appimage "mgba-emu/mgba"         "AppImage"   "mGBA.AppImage"         || sudo pacman -S --noconfirm mgba
download_appimage "cemu-project/Cemu"     "AppImage"   "Cemu.AppImage"         || sudo pacman -S --noconfirm
download_appimage "stenzek/duckstation"   "AppImage"   "duckstation-qt.AppImage" || yay -S --noconfirm duckstation

# ── Pacman — émulateurs sans AppImage fiable ─────────────
info "Installation des émulateurs pacman (sans AppImage officielle)..."
sudo pacman -S --noconfirm \
    dolphin-emu \
    ppsspp \
    desmume
success "Émulateurs pacman installés (dolphin, ppsspp, desmume)"

# ── AUR — ryujinx-canary (binaire, pas AppImage) ─────────
info "Installation de Ryujinx Canary (fork Ryubing) depuis l'AUR..."
if command -v ryujinx &>/dev/null; then
    success "Ryujinx déjà installé, skip."
else
    yay -S --noconfirm ryujinx-canary
    success "Ryujinx Canary installé"
fi

# ── Wine Staging & outils (pacman) ───────────────────────
info "Installation de Wine Staging..."
sudo pacman -S --noconfirm \
    wine-staging \
    wine-gecko \
    wine-mono \
    winetricks
success "Wine Staging installé"

# ── ProtonPlus (AUR) ─────────────────────────────────────
info "Installation de ProtonPlus (gestionnaire Proton/Wine)..."
if command -v protonplus &>/dev/null; then
    success "ProtonPlus déjà installé, skip."
else
    yay -S --noconfirm protonplus
    success "ProtonPlus installé"
fi

# ── BGB — Game Boy (binaire Windows via Wine) ────────────
info "Installation de BGB (émulateur Game Boy, binaire Windows via Wine)..."
BGB_DIR="$HOME/.local/share/bgb"
if [[ -f "$BGB_DIR/bgb.exe" ]]; then
    success "BGB déjà installé, skip."
else
    mkdir -p "$BGB_DIR"
    mkdir -p "$HOME/.local/bin"
    curl -fsSL --progress-bar -o /tmp/bgb.zip "https://bgb.bircd.org/bgb.zip"
    unzip -o /tmp/bgb.zip -d "$BGB_DIR"
    rm /tmp/bgb.zip
    cat > "$HOME/.local/bin/bgb" << EOF
#!/bin/bash
wine "$BGB_DIR/bgb.exe" "\$@"
EOF
    chmod +x "$HOME/.local/bin/bgb"
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/bgb.desktop" << EOF
[Desktop Entry]
Name=BGB
GenericName=Game Boy Emulator
Exec=wine $BGB_DIR/bgb.exe
Icon=mgba
Terminal=false
Type=Application
Categories=Game;Emulator;
EOF
    success "BGB installé dans $BGB_DIR — lancé via Wine"
fi

#  CONFIGURATION SESSION (KDE ou XFCE)
# ══════════════════════════════════════════════════════════
banner "CONFIGURATION SESSION — ${XDG_CURRENT_DESKTOP:-inconnue}"

if [[ "${XDG_CURRENT_DESKTOP:-}" == "KDE" ]]; then
    info "Session KDE détectée"

    # ── Thème Breeze Sombre ──────────────────────────
    info "Application du thème Breeze Sombre..."
    mkdir -p ~/.config
    cat > ~/.config/kdeglobals << EOF
[General]
ColorScheme=BreezeDark

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop
widgetStyle=Breeze
EOF
    success "Thème Breeze Sombre appliqué"

    # ── Langue anglais US (clavier FR conservé) ──────
    info "Langue KDE → English (US) — clavier FR conservé..."
    cat > ~/.config/plasma-localerc << EOF
[Formats]
LANG=en_US.UTF-8
LC_ADDRESS=en_US.UTF-8
LC_MEASUREMENT=en_US.UTF-8
LC_MONETARY=en_US.UTF-8
LC_NAME=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
LC_PAPER=en_US.UTF-8
LC_TELEPHONE=en_US.UTF-8
LC_TIME=en_US.UTF-8

[Translations]
LANGUAGE=en_US
EOF
    success "Langue KDE configurée : English (US) — clavier AZERTY conservé"

    # ── Langue SDDM via drop-in systemd ──────────────
    info "Langue SDDM → English (US) via systemd drop-in..."
    sudo mkdir -p /etc/systemd/system/sddm.service.d
    sudo bash -c 'cat > /etc/systemd/system/sddm.service.d/locale.conf << EOF
[Service]
Environment=LANG=en_US.UTF-8
EOF'
    sudo systemctl daemon-reload
    success "Langue SDDM configurée via systemd drop-in"

    # ── Fond d'écran SDDM ────────────────────────────
    info "Application du fond d'écran SDDM (Breeze Dark)..."
    WALLPAPER="/usr/share/wallpapers/Next/contents/images_dark/5120x2880.png"
    if sudo test -f "$WALLPAPER"; then
        sudo bash -c "cat > /usr/share/sddm/themes/breeze/theme.conf.user << EOF
[General]
background=$WALLPAPER
EOF"
        success "Fond SDDM appliqué : $WALLPAPER"
    else
        warn "Wallpaper introuvable : $WALLPAPER — fond SDDM par défaut conservé."
    fi

elif [[ "${XDG_CURRENT_DESKTOP:-}" == "XFCE" ]]; then
    info "Session XFCE détectée"

    # ── Langue anglais US (clavier FR conservé) ──────
    info "Langue XFCE → English (US) — clavier FR conservé..."
    sed -i '/^export LANG=/d;/^export LC_/d;/^export LANGUAGE=/d' ~/.xprofile 2>/dev/null || true
    cat >> ~/.xprofile << EOF

# Langue English US — ajouté par 2-post-install
export LANG=en_US.UTF-8
export LANGUAGE=en_US
export LC_ALL=en_US.UTF-8
EOF
    success "Langue XFCE configurée : English (US) — clavier AZERTY conservé"

else
    warn "Session non reconnue (${XDG_CURRENT_DESKTOP:-non définie}) — configuration thème/langue ignorée."
    warn "Lance ce script depuis une session KDE ou XFCE."
fi

# ══════════════════════════════════════════════════════════
#  FIN
# ══════════════════════════════════════════════════════════
echo -e "\n${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           ✅ POST-INSTALLATION TERMINÉE !                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Redémarre pour appliquer le mode GPU hybride :             ║"
echo "║    sudo reboot                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  COMMANDES UTILES — envycontrol :                           ║"
echo "║    envycontrol --query           → mode GPU actuel          ║"
echo "║    sudo envycontrol -s hybrid    → AMD + NVIDIA à la demande║"
echo "║    sudo envycontrol -s nvidia    → NVIDIA uniquement        ║"
echo "║    sudo envycontrol -s integrated→ AMD uniquement (batterie)║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  DANS KDE :                                                 ║"
echo "║    Clic droit sur une app → 'Lancer avec GPU dédié'         ║"
echo "║    (via switcheroo-control, déjà actif)                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  STEAM :                                                    ║"
echo "║    Propriétés du jeu → Options de lancement :               ║"
echo "║    prime-run %command%                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Déconnexion ──────────────────────────────────
echo -e "${YELLOW}⚠️  Déconnecte-toi et reconnecte-toi pour appliquer le thème et la langue.${NC}"