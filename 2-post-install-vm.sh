#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║      ARCH LINUX POST-INSTALL — VMware Workstation            ║
# ║   À lancer APRÈS le premier démarrage dans KDE Plasma        ║
# ║   Installe : yay · Waterfox                                  ║
# ║   ⚠️  Pas d'envycontrol/NVIDIA — version VM uniquement       ║
# ╚══════════════════════════════════════════════════════════════╝
# Usage : bash 2-post-install-vm.sh

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
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
EOF

    success "Waterfox $LATEST_VERSION installé"
fi

# ══════════════════════════════════════════════════════════
#  CONFIGURATION SESSION (KDE ou XFCE)
# ══════════════════════════════════════════════════════════
banner "CONFIGURATION SESSION — ${XDG_CURRENT_DESKTOP:-inconnue}"

if [[ "${XDG_CURRENT_DESKTOP:-}" == "KDE" ]]; then
    info "Session KDE détectée"

    # ── Thème Breeze Sombre ──────────────────────────
    info "Application du thème Breeze Sombre..."
    mkdir -p ~/.config
    # Écriture directe dans kdeglobals (kwriteconfig5 non disponible sans paquet extra)
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
    mkdir -p ~/.config
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
    # ~/.xprofile est sourcé par XFCE au démarrage de session
    # On retire toute ligne LANG/LC_ existante puis on ajoute les nouvelles
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
echo "║        ✅ POST-INSTALLATION VM TERMINÉE !                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Logiciels installés :                                      ║"
echo "║    yay        → AUR helper                                  ║"
echo "║    Waterfox   → /opt/waterfox                               ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Intégration VMware (open-vm-tools) :                       ║"
echo "║    Clipboard bidirectionnel   → actif                       ║"
echo "║    Résolution automatique     → actif                       ║"
echo "║    Dossiers partagés          → VM → Settings → Sharing     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Déconnexion ──────────────────────────────────
echo -e "${YELLOW}⚠️  Déconnecte-toi et reconnecte-toi pour appliquer le thème et la langue.${NC}"