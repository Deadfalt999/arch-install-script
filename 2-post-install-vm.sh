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
