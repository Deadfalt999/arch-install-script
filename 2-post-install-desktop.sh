#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║      ARCH LINUX POST-INSTALL — Desktop AMD CPU + AMD GPU     ║
# ║   À lancer APRÈS le premier démarrage dans KDE Plasma        ║
# ║   Installe : yay · Waterfox                                  ║
# ║   ⚠️  Pas d'envycontrol/NVIDIA — GPU AMD uniquement          ║
# ╚══════════════════════════════════════════════════════════════╝
# Usage : bash 2-post-install-desktop.sh

set -uo pipefail
trap 's=$?; echo -e "\n❌ Erreur ligne $LINENO : $BASH_COMMAND\n"; exit $s' ERR

GREEN='\033[0;32m'; BLUE='\033[0;34m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

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

    success "Waterfox $LATEST_VERSION installé dans /opt/waterfox"
fi


# ══════════════════════════════════════════════════════════
#  GEAR LEVER (GESTIONNAIRE D'APPIMAGE)
# ══════════════════════════════════════════════════════════
banner "GEAR LEVER — GESTIONNAIRE D'APPIMAGE"
if command -v gearlever &>/dev/null; then
    success "Gear Lever déjà installé, skip."
else
    info "Installation de Gear Lever (AUR)..."
    # Augmenter timeout sudo
    sudo -v
    sudo sh -c 'echo "Defaults timestamp_timeout=60" > /etc/sudoers.d/timeout'
    info "Installation de dwarfs (dépendance)..."
    yay -S --noconfirm --mflags "--nocheck" dwarfs || warn "dwarfs échoué"
    info "Installation de gearlever..."
    yay -S --noconfirm --mflags "--nocheck" gearlever
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
    local appname="${name%.AppImage}"
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
    # Créer un .desktop pour l'intégration KDE
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/${appname}.desktop" << EOF
[Desktop Entry]
Name=$appname
Exec=$APPDIR/$name
Icon=$appname
Terminal=false
Type=Application
Categories=Game;
EOF
    success "$name installé dans $APPDIR/ — raccourci KDE créé"
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
if [[ -f "$APPDIR/mGBA.AppImage" ]]; then
    success "mGBA déjà présent, skip."
else
    info "Téléchargement de mGBA (AppImage officielle — mgba.io)..."
    curl -fsSL --progress-bar \
        -o "$APPDIR/mGBA.AppImage" \
        "https://s3.amazonaws.com/mgba/mGBA-build-latest-appimage-x64.appimage"
    chmod +x "$APPDIR/mGBA.AppImage"
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/mGBA.desktop" << EOF
[Desktop Entry]
Name=mGBA
GenericName=Game Boy / GBA Emulator
Exec=$APPDIR/mGBA.AppImage
Icon=mgba
Terminal=false
Type=Application
Categories=Game;Emulator;
EOF
    success "mGBA AppImage installé"
fi

download_appimage "cemu-project/Cemu"     "AppImage"   "Cemu.AppImage"         || yay -S --noconfirm cemu-bin
download_appimage "stenzek/duckstation"   "AppImage"   "duckstation-qt.AppImage" || yay -S --noconfirm duckstation-qt-bin


# ── Dolphin (GameCube / Wii) — compilation via Docker ────
banner "DOLPHIN — COMPILATION VIA DOCKER (Ubuntu 24.04 + GCC 13)"

DOLPHIN_DIR="$HOME/.local/share/dolphin-bin"
DOLPHIN_BIN="$DOLPHIN_DIR/dolphin-emu"

if [[ -f "$DOLPHIN_BIN" ]]; then
    success "Dolphin déjà installé, skip."
else
    info "Installation de Docker..."
    sudo pacman -S --noconfirm docker
    sudo systemctl start docker

    info "Compilation de Dolphin dans Ubuntu 24.04 (GCC 13, compatible C++20)..."
    info "Vérification des conteneurs Docker existants..."
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^dolphin-build$"; then
        warn "Conteneur 'dolphin-build' existant détecté — suppression et relance..."
        sudo docker rm -f dolphin-build 2>/dev/null || true
        success "Conteneur 'dolphin-build' supprimé"
    fi

    sudo docker run --name dolphin-build ubuntu:24.04 bash -c "
        export DEBIAN_FRONTEND=noninteractive &&
        apt-get update -qq &&
        apt-get install -y -qq \
            cmake ninja-build git gcc g++ pkg-config \
            libgl1-mesa-dev libx11-dev libxrandr-dev \
            libxi-dev libxext-dev libxfixes-dev libxxf86vm-dev \
            libsdl2-dev libevdev-dev \
            libsfml-dev libminiupnpc-dev \
            libmbedtls-dev libcurl4-openssl-dev \
            libhidapi-dev libbluetooth-dev \
            libvulkan-dev \
            libwayland-dev wayland-protocols \
            qt6-base-dev qt6-base-private-dev libqt6svg6-dev qt6-multimedia-dev \
            libavcodec-dev libavformat-dev libswscale-dev libpng-dev \
            libasound2-dev libusb-1.0-0-dev \
            libfmt-dev liblzo2-dev libzstd-dev \
            libenet-dev libpugixml-dev libxxhash-dev \
            glslang-tools libspirv-cross-c-shared-dev \
            libopenal-dev libspng-dev \
            zip unzip &&
        git clone --depth=1 https://github.com/dolphin-emu/dolphin.git /dolphin &&
        cd /dolphin &&
        git -c submodule.'Externals/Qt'.update=none \
            -c submodule.'Externals/FFmpeg-bin'.update=none \
            -c submodule.'Externals/libadrenotools'.update=none \
            submodule update --init --recursive &&
        mkdir build && cd build &&
        cmake .. -GNinja \
            -DCMAKE_BUILD_TYPE=Release \
            -DLINUX_LOCAL_DEV=true \
            -DUSE_SYSTEM_LIBS=AUTO \
            -DUSE_SYSTEM_MINIZIP_NG=OFF \
            -DUSE_SYSTEM_SFML=OFF \
            -DUSE_SYSTEM_MBEDTLS=OFF \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 &&
        ninja -j\$(nproc)
    " && {
        info "Extraction des binaires compilés..."
        mkdir -p "$DOLPHIN_DIR"
        sudo docker cp dolphin-build:/dolphin/build/Binaries/dolphin-emu "$DOLPHIN_DIR/"
        sudo docker cp dolphin-build:/dolphin/build/Binaries/dolphin-tool "$DOLPHIN_DIR/" 2>/dev/null || true

        info "Création du symlink..."
        mkdir -p "$HOME/.local/bin"
        ln -sf "$DOLPHIN_BIN" "$HOME/.local/bin/dolphin-emu"

        info "Création du raccourci bureau..."
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/dolphin-emu.desktop" << EOF
[Desktop Entry]
Name=Dolphin Emulator
GenericName=GameCube / Wii Emulator
Exec=$DOLPHIN_BIN
Icon=dolphin-emu
Terminal=false
Type=Application
Categories=Game;Emulator;
EOF
        success "Dolphin compilé et installé via Docker (Ubuntu 24.04 GCC 13)"
    } || {
        warn "Compilation Dolphin échouée — fallback dolphin-emu pacman..."
        sudo pacman -S --noconfirm dolphin-emu
    }

    info "Nettoyage Docker (conteneur + image)..."
    sudo docker rm dolphin-build 2>/dev/null || true
    sudo docker rmi ubuntu:24.04 2>/dev/null || true
    sudo systemctl stop docker
    success "Docker nettoyé"
fi



# ── AppImage — melonDS (Nintendo DS) — officielle ────────
# melonDS — AppImage dans un zip sur les releases officielles
if [[ -f "$APPDIR/melonDS.AppImage" ]]; then
    success "melonDS déjà présent, skip."
else
    info "Téléchargement de melonDS (AppImage officielle dans zip)..."
    MELON_URL=$(curl -fsSL "https://api.github.com/repos/melonDS-emu/melonDS/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*appimage[^"]*x86_64[^"]*\.zip"' \
        | head -1 | cut -d'"' -f4)
    if [[ -n "$MELON_URL" ]]; then
        curl -fsSL --progress-bar -o /tmp/melonDS-appimage.zip "$MELON_URL"
        unzip -o /tmp/melonDS-appimage.zip "*.AppImage" -d /tmp/melonds-extract/
        MELON_APPIMAGE=$(find /tmp/melonds-extract -name "*.AppImage" | head -1)
        if [[ -n "$MELON_APPIMAGE" ]]; then
            cp "$MELON_APPIMAGE" "$APPDIR/melonDS.AppImage"
            chmod +x "$APPDIR/melonDS.AppImage"
            success "melonDS AppImage installé"
        else
            warn "AppImage introuvable dans le zip melonDS"
        fi
        rm -f /tmp/melonDS-appimage.zip
        rm -rf /tmp/melonds-extract
    else
        warn "URL melonDS introuvable — fallback AUR..."
        yay -S --noconfirm melonds-bin
    fi
fi



# ── AppImage — PPSSPP (PSP) ───────────────────────────────
download_appimage "hrydgard/ppsspp" "AppImage" "PPSSPP.AppImage" || sudo pacman -S --noconfirm ppsspp

# ── AppImage — Ryubing/Canary (Nintendo Switch) ──────────
info "Téléchargement de Ryujinx Canary (AppImage officielle Ryubing)..."
if [[ -f "$APPDIR/Ryujinx.AppImage" ]]; then
    success "Ryujinx déjà présent, skip."
else
    RYUBING_URL=$(curl -fsSL "https://git.ryujinx.app/Ryubing/Canary/releases" \
        | tr '""><> ' '\n' \
        | grep -Eoi "http.*\.AppImage$" \
        | grep -i "x64\|x86_64\|amd64" \
        | head -1)
    if [[ -n "$RYUBING_URL" ]]; then
        curl -fsSL --progress-bar -o "$APPDIR/Ryujinx.AppImage" "$RYUBING_URL"
        chmod +x "$APPDIR/Ryujinx.AppImage"
        success "Ryujinx Canary AppImage installé"
    else
        warn "URL Ryubing introuvable — fallback AUR..."
        yay -S --noconfirm ryujinx-canary
    fi
fi

# ── PC Ports — OpenMW & Daggerfall Unity ─────────────────
banner "PC PORTS (NON-HARBOURMASTERS)"
warn "⚠️  Ces ports nécessitent les fichiers du jeu original"

# OpenMW — tarball officiel depuis GitHub (OpenMW/openmw)
OPENMW_DIR="$HOME/.local/share/openmw-bin"
info "Installation de OpenMW (Morrowind engine — tarball GitHub)..."
if [[ -f "$OPENMW_DIR/openmw" ]] || command -v openmw &>/dev/null; then
    success "OpenMW déjà installé, skip."
else
    OPENMW_URL=$(curl -fsSL "https://api.github.com/repos/OpenMW/openmw/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*Linux[^"]*\.tar\.gz"' \
        | head -1 \
        | cut -d'"' -f4)
    if [[ -n "$OPENMW_URL" ]]; then
        mkdir -p "$OPENMW_DIR"
        curl -fsSL --progress-bar -o /tmp/openmw-linux.tar.gz "$OPENMW_URL"
        tar -xzf /tmp/openmw-linux.tar.gz -C "$OPENMW_DIR" --strip-components=1
        rm /tmp/openmw-linux.tar.gz
        mkdir -p "$HOME/.local/bin"
        ln -sf "$OPENMW_DIR/openmw-launcher" "$HOME/.local/bin/openmw-launcher"
        ln -sf "$OPENMW_DIR/openmw" "$HOME/.local/bin/openmw"
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/openmw.desktop" << EOF
[Desktop Entry]
Name=OpenMW
GenericName=Morrowind Engine
Exec=$OPENMW_DIR/openmw-launcher
Icon=openmw-launcher
Terminal=false
Type=Application
Categories=Game;
EOF
        success "OpenMW installé — requiert les fichiers de Morrowind (TES III)"
        warn "Lance openmw-launcher et pointe vers tes fichiers Morrowind"
    else
        warn "URL OpenMW introuvable — fallback pacman..."
        sudo pacman -S --noconfirm openmw
    fi
fi

# Daggerfall Unity — zip Linux officiel depuis GitHub (Interkarma/daggerfall-unity)
DFU_DIR="$HOME/.local/share/daggerfall-unity"
info "Installation de Daggerfall Unity (zip GitHub)..."
if [[ -f "$DFU_DIR/DaggerfallUnity" ]]; then
    success "Daggerfall Unity déjà installé, skip."
else
    DFU_URL=$(curl -fsSL "https://api.github.com/repos/Interkarma/daggerfall-unity/releases/latest" \
        | grep browser_download_url \
        | grep -i linux \
        | grep "\.zip" \
        | head -1 \
        | cut -d'"' -f4)
    if [[ -n "$DFU_URL" ]]; then
        mkdir -p "$DFU_DIR"
        curl -fsSL --progress-bar -o /tmp/daggerfall-unity-linux.zip "$DFU_URL"
        unzip -o /tmp/daggerfall-unity-linux.zip -d "$DFU_DIR"
        rm /tmp/daggerfall-unity-linux.zip
        chmod +x "$DFU_DIR/DaggerfallUnity" 2>/dev/null || true
        mkdir -p "$HOME/.local/bin"
        ln -sf "$DFU_DIR/DaggerfallUnity" "$HOME/.local/bin/daggerfall-unity"
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/daggerfall-unity.desktop" << EOF
[Desktop Entry]
Name=Daggerfall Unity
GenericName=TES II: Daggerfall
Exec=$DFU_DIR/DaggerfallUnity
Icon=daggerfall
Terminal=false
Type=Application
Categories=Game;
EOF
        success "Daggerfall Unity installé dans $DFU_DIR"
        warn "Les fichiers DOS Daggerfall sont gratuits sur Steam ou ici :"
        warn "https://github.com/Interkarma/daggerfall-unity/wiki/Installing-Daggerfall-Unity-Cross-Platform"
    else
        warn "URL Daggerfall Unity introuvable — fallback AUR..."
        yay -S --noconfirm daggerfall-unity-bin
    fi
fi


# ── HarbourMasters PC Ports (AppImages) ──────────────────
banner "HARBOURMASTERS PC PORTS"
warn "⚠️  Ces ports nécessitent un ROM légalement obtenu placé dans ~/Applications/"

# Ship of Harkinian — Zelda: Ocarina of Time
if [[ -f "$APPDIR/ShipOfHarkinian.AppImage" ]]; then
    success "Ship of Harkinian déjà présent, skip."
else
    info "Téléchargement de Ship of Harkinian (Zelda: OoT)..."
    download_appimage "HarbourMasters/Shipwright" "AppImage" "ShipOfHarkinian.AppImage" \
        || warn "Ship of Harkinian introuvable — télécharge manuellement depuis github.com/HarbourMasters/Shipwright"
fi

# 2 Ship 2 Harkinian — Zelda: Majora's Mask
if [[ -f "$APPDIR/2Ship2Harkinian.AppImage" ]]; then
    success "2 Ship 2 Harkinian déjà présent, skip."
else
    info "Téléchargement de 2 Ship 2 Harkinian (Zelda: MM)..."
    download_appimage "HarbourMasters/2ship2harkinian" "AppImage" "2Ship2Harkinian.AppImage" \
        || warn "2 Ship 2 Harkinian introuvable — télécharge manuellement depuis github.com/HarbourMasters/2ship2harkinian"
fi

# Starship — Star Fox 64
if [[ -f "$APPDIR/Starship.AppImage" ]]; then
    success "Starship déjà présent, skip."
else
    info "Téléchargement de Starship (Star Fox 64)..."
    download_appimage "HarbourMasters/Starship" "AppImage" "Starship.AppImage" \
        || warn "Starship introuvable — télécharge manuellement depuis github.com/HarbourMasters/Starship"
fi

# SpaghettiKart — Mario Kart 64
if [[ -f "$APPDIR/SpaghettiKart.AppImage" ]]; then
    success "SpaghettiKart déjà présent, skip."
else
    info "Téléchargement de SpaghettiKart (Mario Kart 64)..."
    download_appimage "HarbourMasters/SpaghettiKart" "AppImage" "SpaghettiKart.AppImage" \
        || warn "SpaghettiKart introuvable — télécharge manuellement depuis github.com/HarbourMasters/SpaghettiKart"
fi
success "Ports HarbourMasters installés dans $APPDIR"


# Ghostship — Super Mario 64 (zip Linux, pas AppImage)
banner "GHOSTSHIP — SUPER MARIO 64 (HarbourMasters)"
warn "⚠️  Nécessite une ROM Super Mario 64 US légalement obtenue"

GHOSTSHIP_DIR="$HOME/.local/share/ghostship"
if [[ -f "$APPDIR/Ghostship.AppImage" ]]; then
    success "Ghostship déjà installé, skip."
else
    info "Récupération de la dernière version de Ghostship..."
    GHOSTSHIP_URL=$(curl -fsSL "https://api.github.com/repos/HarbourMasters/Ghostship/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*Linux[^"]*\.zip"' \
        | head -1 \
        | cut -d'"' -f4)
    if [[ -n "$GHOSTSHIP_URL" ]]; then
        mkdir -p "$GHOSTSHIP_DIR"
        curl -fsSL --progress-bar -o /tmp/ghostship-linux.zip "$GHOSTSHIP_URL"
        unzip -o /tmp/ghostship-linux.zip -d "$GHOSTSHIP_DIR"
        rm /tmp/ghostship-linux.zip
        # L'AppImage est dans le zip
        APPIMAGE=$(find "$GHOSTSHIP_DIR" -name "*.AppImage" | head -1)
        if [[ -n "$APPIMAGE" ]]; then
            chmod +x "$APPIMAGE"
            cp "$APPIMAGE" "$APPDIR/Ghostship.AppImage"
            rm -rf "$GHOSTSHIP_DIR"
            success "Ghostship AppImage installé dans $APPDIR"
        else
            warn "AppImage introuvable dans le zip Ghostship"
        fi
    else
        warn "URL Ghostship introuvable — télécharge manuellement depuis github.com/HarbourMasters/Ghostship"
    fi
fi


# ── UZDoom (Doom engine) — AppImage officielle GitHub ────
banner "UZDOOM — APPIMAGE OFFICIELLE"

if [[ -f "$APPDIR/UZDoom.AppImage" ]]; then
    success "UZDoom déjà présent, skip."
else
    info "Téléchargement de UZDoom AppImage depuis GitHub (UZDoom/UZDoom)..."
    UZDOOM_URL=$(curl -fsSL "https://api.github.com/repos/UZDoom/UZDoom/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*Linux[^"]*\.AppImage"' \
        | grep -v Legacy \
        | head -1 \
        | cut -d'"' -f4)
    if [[ -n "$UZDOOM_URL" ]]; then
        curl -fsSL --progress-bar -o "$APPDIR/UZDoom.AppImage" "$UZDOOM_URL"
        chmod +x "$APPDIR/UZDoom.AppImage"
        success "UZDoom AppImage installé : $UZDOOM_URL"
    else
        warn "URL UZDoom introuvable — fallback AUR..."
        yay -S --noconfirm uzdoom
    fi
fi

# ── Yamagi Quake II — AppImage non-officielle (tx00100xt) ─
banner "YAMAGI QUAKE II — APPIMAGE"

if [[ -f "$APPDIR/YamagiQ2.AppImage" ]]; then
    success "Yamagi Quake II déjà présent, skip."
else
    info "Téléchargement de Yamagi Quake II AppImage (tx00100xt/yquake2-appimage)..."
    YQ2_URL=$(curl -fsSL "https://api.github.com/repos/tx00100xt/yquake2-appimage/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*x86_64\.AppImage"' \
        | head -1 \
        | cut -d'"' -f4)
    if [[ -n "$YQ2_URL" ]]; then
        curl -fsSL --progress-bar -o "$APPDIR/YamagiQ2.AppImage" "$YQ2_URL"
        chmod +x "$APPDIR/YamagiQ2.AppImage"
        success "Yamagi Quake II AppImage installé : $YQ2_URL"
    else
        warn "URL Yamagi Q2 introuvable — fallback AUR..."
        yay -S --noconfirm yamagi-quake2
    fi
fi

# ── ECWolf (Wolfenstein 3D) — compilation via Docker ─────
banner "ECWOLF — COMPILATION VIA DOCKER (Ubuntu 20.04)"

ECWOLF_DIR="$HOME/.local/share/ecwolf"
ECWOLF_BIN="$ECWOLF_DIR/ecwolf"

if [[ -f "$ECWOLF_BIN" ]]; then
    success "ECWolf déjà compilé, skip."
else
    info "Installation de Docker..."
    sudo pacman -S --noconfirm docker
    sudo systemctl start docker

    info "Compilation de ECWolf dans un conteneur Ubuntu 20.04 (GCC 9, sans bug tmemory.h)..."
    info "Vérification des conteneurs Docker existants..."
    if sudo docker ps -a --format '{{.Names}}' | grep -q "^ecwolf-build$"; then
        warn "Conteneur 'ecwolf-build' existant détecté — suppression et relance..."
        sudo docker rm -f ecwolf-build 2>/dev/null || true
        success "Conteneur 'ecwolf-build' supprimé"
    fi

    sudo docker run --name ecwolf-build ubuntu:20.04 bash -c "
        export DEBIAN_FRONTEND=noninteractive &&
        apt-get update -qq &&
        apt-get install -y -qq \
            cmake make pkg-config gcc g++ wget \
            zlib1g-dev libbz2-dev libjpeg-dev \
            libsdl2-dev libsdl2-mixer-dev libsdl2-net-dev \
            libgtk-3-dev &&
        wget -q -O /ecwolf.tar.gz https://bitbucket.org/ecwolf/ecwolf/get/1.4.1.tar.gz &&
        mkdir -p /ecwolf && tar -xzf /ecwolf.tar.gz -C /ecwolf --strip-components=1 &&
        cd /ecwolf && mkdir build && cd build &&
        cmake .. -DCMAKE_BUILD_TYPE=Release &&
        make -j\$(nproc)
    " && {
        info "Extraction des binaires compilés..."
        mkdir -p "$ECWOLF_DIR"
        sudo docker cp ecwolf-build:/ecwolf/build/ecwolf "$ECWOLF_DIR/"
        sudo docker cp ecwolf-build:/ecwolf/build/ecwolf.pk3 "$ECWOLF_DIR/"

        info "Création du symlink..."
        mkdir -p "$HOME/.local/bin"
        ln -sf "$ECWOLF_BIN" "$HOME/.local/bin/ecwolf"

        info "Création du raccourci bureau..."
        mkdir -p "$HOME/.local/share/applications"
        cat > "$HOME/.local/share/applications/ecwolf.desktop" << EOF
[Desktop Entry]
Name=ECWolf
GenericName=Wolfenstein 3D
Exec=$ECWOLF_BIN
Icon=wolf3d
Terminal=false
Type=Application
Categories=Game;
EOF
        success "ECWolf compilé et installé depuis Ubuntu 20.04"
    } || {
        warn "Compilation ECWolf échouée — fallback AUR..."
        yay -S --noconfirm ecwolf
    }

    info "Nettoyage Docker (conteneur + image)..."
    sudo docker rm ecwolf-build 2>/dev/null || true
    sudo docker rmi ubuntu:20.04 2>/dev/null || true
    sudo systemctl stop docker
    success "Docker nettoyé"
fi



banner "VKQUAKE — COMPILATION DEPUIS SOURCE"

_build_vkquake() {
    local _VKDIR="$HOME/.local/share/vkquake-source"
    local _VKBIN="$_VKDIR/build/vkquake"

    info "Installation des dépendances de compilation VkQuake..."
    sudo pacman -S --noconfirm \
        git meson ninja pkg-config gcc \
        flac libvorbis mpg123 opusfile \
        sdl2 vulkan-headers vulkan-icd-loader \
        glslang spirv-tools \
        libx11 libgl
    success "Dépendances VkQuake installées"

    info "Clonage de VkQuake depuis GitHub..."
    [[ -d "$_VKDIR" ]] && rm -rf "$_VKDIR"
    git clone https://github.com/Novum/vkQuake.git "$_VKDIR" || {
        warn "Clonage échoué — fallback AUR vkquake..."
        yay -S --noconfirm vkquake
        return 0
    }

    cd "$_VKDIR"

    info "Configuration Meson (depuis $_VKDIR)..."
    meson setup build --buildtype=release || {
        warn "Meson échoué — fallback AUR vkquake..."
        yay -S --noconfirm vkquake
        cd ~
        return 0
    }

    info "Compilation en cours (peut prendre quelques minutes)..."
    ninja -C build || {
        warn "Compilation échouée — fallback AUR vkquake..."
        yay -S --noconfirm vkquake
        cd ~
        return 0
    }

    mkdir -p "$HOME/.local/bin"
    ln -sf "$_VKBIN" "$HOME/.local/bin/vkquake"

    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/vkquake.desktop" << EOF
[Desktop Entry]
Name=vkQuake
GenericName=Quake (Vulkan)
Exec=$_VKBIN
Icon=quake
Terminal=false
Type=Application
Categories=Game;
EOF

    cd ~
    success "VkQuake compilé et installé depuis source (Vulkan)"
}

if [[ -f "$HOME/.local/share/vkquake-source/build/vkquake" ]]; then
    success "VkQuake déjà compilé, skip."
else
    _build_vkquake
fi
unset -f _build_vkquake








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

# Langue English US — ajouté par 2-post-install-desktop
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
echo -e "
${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           ✅ POST-INSTALLATION TERMINÉE !                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  LOGICIELS INSTALLÉS :                                      ║"
echo "║                                                              ║"
echo "║  Outils AUR / Système                                        ║"
echo "║    yay              → AUR helper                            ║"
echo "║    ProtonPlus        → gestionnaire Proton/Wine              ║"
echo "║    Gear Lever        → gestionnaire AppImages                ║"
echo "║    wine-staging      → compatibilité Windows                 ║"
echo "║    Waterfox          → navigateur (tarball officiel)         ║"
echo "║                                                              ║"
echo "║  Émulateurs — AppImages (~/Applications/)                    ║"
echo "║    RetroArch         → multi-systèmes (nightly)             ║"
echo "║    PCSX2             → PlayStation 2                        ║"
echo "║    mGBA              → Game Boy / GBA                       ║"
echo "║    Cemu              → Wii U                                ║"
echo "║    DuckStation       → PlayStation 1                        ║"
echo "║    PPSSPP            → PSP                                  ║"
echo "║    melonDS           → Nintendo DS                          ║"
echo "║    Ryujinx Canary    → Nintendo Switch                      ║"
echo "║                                                              ║"
echo "║  PC Ports HarbourMasters (~/Applications/) ⚠️ ROM requise   ║"
echo "║    Ship of Harkinian → Zelda: Ocarina of Time               ║"
echo "║    2 Ship 2 Harkinian→ Zelda: Majora's Mask                 ║"
echo "║    Starship           → Star Fox 64                         ║"
echo "║    SpaghettiKart      → Mario Kart 64                       ║"
echo "║    Ghostship          → Super Mario 64                      ║"
echo "║                                                              ║"
echo "║  Émulateurs — Packages système                               ║"
echo "║    Dolphin            → GameCube / Wii (compilé source)     ║"
echo "║    BGB                → Game Boy (Windows .exe via Wine)    ║"
echo "║                                                              ║"
echo "║  Source Ports                                                ║"
echo "║    vkQuake            → Quake 1 Vulkan (compilé source)     ║"
echo "║    UZDoom             → Doom engine (AppImage)              ║"
echo "║    Yamagi Quake II    → Quake II (AppImage)                 ║"
echo "║    ECWolf             → Wolfenstein 3D (Docker/source)      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  GPU — envycontrol (laptop uniquement) :                    ║"
echo "║    envycontrol --query           → mode GPU actuel          ║"
echo "║    sudo envycontrol -s hybrid    → AMD + NVIDIA à la demande║"
echo "║    sudo envycontrol -s nvidia    → NVIDIA uniquement        ║"
echo "║    sudo envycontrol -s integrated→ AMD uniquement (batterie)║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  STEAM — lancer un jeu sur NVIDIA :                         ║"
echo "║    Propriétés du jeu → Options de lancement :               ║"
echo "║    prime-run %command%                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Déconnexion ──────────────────────────────────
