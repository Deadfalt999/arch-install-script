#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║         ARCH LINUX — SCRIPT D'INSTALLATION UNIFIÉ           ║
# ║  Laptop AMD/Intel + NVIDIA · Desktop AMD/Intel · VMware     ║
# ║  Détection automatique de la configuration matérielle       ║
# ╚══════════════════════════════════════════════════════════════╝
# Usage : bash 1-install.sh
# ⚠️  Ce script va EFFACER ENTIÈREMENT le disque cible !

set -uo pipefail
trap 's=$?; echo -e "\n❌ Erreur ligne $LINENO : $BASH_COMMAND\n"; exit $s' ERR

# ══════════════════════════════════════════════════════════
#  COULEURS & FONCTIONS
# ══════════════════════════════════════════════════════════
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "\n${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }
banner()  { echo -e "\n${BOLD}══ $1 ══${NC}"; }

ask() {
    local prompt="$1" default="${2:-o}" answer
    while true; do
        read -rp "$(echo -e "${YELLOW}$prompt${NC} [O/n]: ")" answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            o|oui|y|yes|1) return 0 ;;
            n|non|no|0)    return 1 ;;
            *) echo -e "  ${RED}→ Répondre par o/oui ou n/non.${NC}" ;;
        esac
    done
}

warn_weak_password() {
    local label="$1" pwd="$2"
    if [[ ${#pwd} -lt 6 ]]; then
        echo -e "\n${RED}${BOLD}⚠️  AVERTISSEMENT — Mot de passe $label trop court${NC}"
        ask "  Continuer quand même ?" "n" || error "Installation annulée."
    fi
}

# ══════════════════════════════════════════════════════════
#  ÉTAPE 1 — DÉTECTION AUTOMATIQUE DU MATÉRIEL
# ══════════════════════════════════════════════════════════
banner "DÉTECTION DU MATÉRIEL"

# Virtualisation
_VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")

# CPU
_CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null | awk '{print $3}')
case "$_CPU_VENDOR" in
    GenuineIntel) _CPU="intel" ;;
    AuthenticAMD) _CPU="amd" ;;
    *)            _CPU="unknown" ;;
esac

# Type machine (laptop vs desktop)
_CHASSIS=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
case "$_CHASSIS" in
    8|9|10|11|14|30|31|32) _MACHINE="laptop" ;;
    3|4|5|6|7|15|16|17|23|24) _MACHINE="desktop" ;;
    *) _MACHINE="unknown" ;;
esac

# GPUs détectés
_GPU_LIST=$(lspci 2>/dev/null | grep -E "VGA|3D|Display" || echo "")
_HAS_NVIDIA=false; _HAS_AMD_GPU=false; _HAS_INTEL_GPU=false
echo "$_GPU_LIST" | grep -qi "nvidia"  && _HAS_NVIDIA=true
echo "$_GPU_LIST" | grep -qi "advanced micro\|amd\|radeon" && _HAS_AMD_GPU=true
echo "$_GPU_LIST" | grep -qi "intel"   && _HAS_INTEL_GPU=true

# Déduire la config
if [[ "$_VIRT" == "vmware" ]]; then
    _CONFIG_AUTO="vm"
elif [[ "$_MACHINE" == "laptop" ]]; then
    if $_HAS_NVIDIA; then
        [[ "$_CPU" == "amd" ]] && _CONFIG_AUTO="laptop-amd-nvidia" || _CONFIG_AUTO="laptop-intel-nvidia"
    elif $_HAS_AMD_GPU; then
        _CONFIG_AUTO="laptop-amd"
    else
        _CONFIG_AUTO="laptop-intel"
    fi
else
    if $_HAS_NVIDIA && ! $_HAS_AMD_GPU; then
        [[ "$_CPU" == "amd" ]] && _CONFIG_AUTO="desktop-amd-nvidia" || _CONFIG_AUTO="desktop-intel-nvidia"
    elif $_HAS_AMD_GPU; then
        [[ "$_CPU" == "amd" ]] && _CONFIG_AUTO="desktop-amd-amd" || _CONFIG_AUTO="desktop-intel-amd"
    else
        _CONFIG_AUTO="desktop-unknown"
    fi
fi

# Afficher le résultat de la détection
echo ""
echo -e "  ${BLUE}Virtualisation${NC}  : $_VIRT"
echo -e "  ${BLUE}CPU${NC}             : $_CPU_VENDOR ($_CPU)"
echo -e "  ${BLUE}Type machine${NC}    : $_MACHINE (chassis $_CHASSIS)"
echo -e "  ${BLUE}GPUs détectés${NC}   :"
echo "$_GPU_LIST" | while IFS= read -r line; do echo "    $line"; done
echo ""

# Table de correspondance lisible
declare -A _CONFIG_LABELS
_CONFIG_LABELS=(
    ["vm"]="VMware Workstation"
    ["laptop-amd-nvidia"]="Laptop AMD CPU + NVIDIA GPU (Optimus)"
    ["laptop-intel-nvidia"]="Laptop Intel CPU + NVIDIA GPU (Optimus)"
    ["laptop-amd"]="Laptop AMD CPU + AMD iGPU"
    ["laptop-intel"]="Laptop Intel CPU + Intel iGPU"
    ["desktop-amd-nvidia"]="Desktop AMD CPU + NVIDIA GPU"
    ["desktop-intel-nvidia"]="Desktop Intel CPU + NVIDIA GPU"
    ["desktop-amd-amd"]="Desktop AMD CPU + AMD GPU"
    ["desktop-intel-amd"]="Desktop Intel CPU + AMD GPU"
)

echo -e "  ${GREEN}→ Config détectée : ${BOLD}${_CONFIG_LABELS[$_CONFIG_AUTO]:-$_CONFIG_AUTO}${NC}"
echo ""

if ask "Confirmer cette configuration ?"; then
    CONFIG="$_CONFIG_AUTO"
else
    echo ""
    echo -e "${BOLD}Sélection manuelle :${NC}"
    echo "  1) VMware Workstation"
    echo "  2) Laptop AMD + NVIDIA (Optimus)"
    echo "  3) Laptop Intel + NVIDIA (Optimus)"
    echo "  4) Laptop AMD (iGPU seul)"
    echo "  5) Laptop Intel (iGPU seul)"
    echo "  6) Desktop AMD + NVIDIA"
    echo "  7) Desktop Intel + NVIDIA"
    echo "  8) Desktop AMD + AMD GPU"
    echo "  9) Desktop Intel + AMD GPU"
    echo ""
    read -rp "$(echo -e "${YELLOW}Choix [1-9]${NC} : ")" _CHOICE
    case "$_CHOICE" in
        1) CONFIG="vm" ;;
        2) CONFIG="laptop-amd-nvidia" ;;
        3) CONFIG="laptop-intel-nvidia" ;;
        4) CONFIG="laptop-amd" ;;
        5) CONFIG="laptop-intel" ;;
        6) CONFIG="desktop-amd-nvidia" ;;
        7) CONFIG="desktop-intel-nvidia" ;;
        8) CONFIG="desktop-amd-amd" ;;
        9) CONFIG="desktop-intel-amd" ;;
        *) error "Choix invalide" ;;
    esac
fi

echo -e "\n${GREEN}Config retenue : ${BOLD}${_CONFIG_LABELS[$CONFIG]}${NC}"

# Dériver les variables de config
_IS_VM=false;        [[ "$CONFIG" == "vm" ]] && _IS_VM=true
_IS_LAPTOP=false;    [[ "$CONFIG" == laptop* ]] && _IS_LAPTOP=true
_OPTIMUS=false;      [[ "$CONFIG" == *nvidia* && "$_IS_LAPTOP" == true ]] && _OPTIMUS=true
_NEED_NVIDIA=false;  [[ "$CONFIG" == *nvidia* ]] && _NEED_NVIDIA=true
_NEED_AMD_GPU=false; [[ "$CONFIG" == *amd-amd* || "$CONFIG" == *intel-amd* || "$CONFIG" == laptop-amd* ]] && _NEED_AMD_GPU=true
_CPU_UCODE="";       [[ "$CONFIG" == *intel* ]] && _CPU_UCODE="intel-ucode" || { $_IS_VM || _CPU_UCODE="amd-ucode"; }

# ══════════════════════════════════════════════════════════
#  ÉTAPE 2 — CONFIGURATION
# ══════════════════════════════════════════════════════════
banner "CONFIGURATION"
echo -e "${BOLD}Appuie sur Entrée pour garder la valeur par défaut.${NC}\n"

echo -e "${BLUE}Disques disponibles :${NC}"
lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | grep "disk" | while IFS= read -r line; do
    echo "  $line"
done
echo ""

# Détection automatique du type de bus et du disque
_DISK_NAME=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}' | head -1)
_TRAN=$(lsblk -d -n -o NAME,TRAN 2>/dev/null | awk '$1=="'"$_DISK_NAME"'"{print $2}' | head -1)

# Prioriser le nom du device pour détecter NVMe
if [[ "$_DISK_NAME" == nvme* ]]; then
    _AUTO_DISK="/dev/${_DISK_NAME}"
    _DISK_TYPE="NVMe"
else
    case "${_TRAN,,}" in
        sata)  _AUTO_DISK="/dev/sda"; _DISK_TYPE="SATA" ;;
        ide)   _AUTO_DISK="/dev/sda"; _DISK_TYPE="IDE" ;;
        scsi)  _AUTO_DISK="/dev/sda"; _DISK_TYPE="SCSI" ;;
        usb)   _AUTO_DISK="/dev/sda"; _DISK_TYPE="USB" ;;
        *)     _AUTO_DISK="/dev/${_DISK_NAME:-sda}"; _DISK_TYPE="inconnu" ;;
    esac
fi

echo -e "  ${GREEN}→ Type détecté : ${BOLD}${_DISK_TYPE}${NC} → ${GREEN}${_AUTO_DISK}${NC}"
echo ""

read -rp "$(echo -e "${YELLOW}Disque cible${NC} [$_AUTO_DISK]: ")" _DISK
DISK="${_DISK:-$_AUTO_DISK}"

# Nommage correct des partitions selon le type de disque
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi
info "Partitions : EFI=$EFI_PART  ROOT=$ROOT_PART"

_DEFAULT_HOST="mon-pc"
$_IS_VM && _DEFAULT_HOST="arch-vm"
$_IS_LAPTOP && _DEFAULT_HOST="mon-laptop"
[[ "$CONFIG" == desktop* ]] && _DEFAULT_HOST="mon-desktop"

read -rp "$(echo -e "${YELLOW}Hostname${NC} [$_DEFAULT_HOST]: ")" _HOSTNAME
HOSTNAME="${_HOSTNAME:-$_DEFAULT_HOST}"

read -rp "$(echo -e "${YELLOW}Nom d'utilisateur${NC} [Admin]: ")" _USERNAME
USERNAME="${_USERNAME:-Admin}"

read -rp "$(echo -e "${YELLOW}Timezone${NC} [Europe/Paris]: ")" _TIMEZONE
TIMEZONE="${_TIMEZONE:-Europe/Paris}"

read -rp "$(echo -e "${YELLOW}Locale${NC} [fr_FR.UTF-8]: ")" _LOCALE
LOCALE="${_LOCALE:-fr_FR.UTF-8}"

read -rp "$(echo -e "${YELLOW}Clavier console${NC} [fr]: ")" _KEYMAP
KEYMAP="${_KEYMAP:-fr}"

# ── Sélection des kernels ─────────────────────────────────
echo ""
echo -e "${BOLD}Kernels disponibles :${NC}"
echo -e "  [1] linux       — kernel standard ${GREEN}✓${NC}"
echo -e "  [2] linux-lts   — kernel Long Term Support ${GREEN}✓${NC}"
echo -e "  [3] linux-zen   — kernel optimisé performance"
echo -e "  [4] linux-hardened — kernel sécurisé"
echo ""
read -rp "$(echo -e "${YELLOW}Sélection kernels${NC} [1 2]: ")" _KERNEL_SEL
_KERNEL_SEL="${_KERNEL_SEL:-1 2}"
KERNELS=""
[[ "$_KERNEL_SEL" == *"1"* ]] && KERNELS="$KERNELS linux"
[[ "$_KERNEL_SEL" == *"2"* ]] && KERNELS="$KERNELS linux-lts"
[[ "$_KERNEL_SEL" == *"3"* ]] && KERNELS="$KERNELS linux-zen"
[[ "$_KERNEL_SEL" == *"4"* ]] && KERNELS="$KERNELS linux-hardened"
KERNELS="${KERNELS## }"
[[ -z "$KERNELS" ]] && KERNELS="linux linux-lts"
echo -e "  → Kernels retenus : ${GREEN}${KERNELS}${NC}"

# ── Sélection des environnements de bureau ────────────────
echo ""
echo -e "${BOLD}Environnements de bureau :${NC}"
echo -e "  [1] KDE Plasma  — Wayland ${GREEN}✓${NC}"
echo -e "  [2] XFCE4       — X11, léger ${GREEN}✓${NC}"
echo -e "  [3] Cinnamon    — X11, stable"
echo -e "  [4] GNOME       — Wayland"
echo -e "  [5] MATE        — X11, très léger"
echo ""
read -rp "$(echo -e "${YELLOW}Sélection DEs${NC} [1 2]: ")" _DE_SEL
_DE_SEL="${_DE_SEL:-1 2}"
INSTALL_KDE=false;      [[ "$_DE_SEL" == *"1"* ]] && INSTALL_KDE=true
INSTALL_XFCE=false;     [[ "$_DE_SEL" == *"2"* ]] && INSTALL_XFCE=true
INSTALL_CINNAMON=false; [[ "$_DE_SEL" == *"3"* ]] && INSTALL_CINNAMON=true
INSTALL_GNOME=false;    [[ "$_DE_SEL" == *"4"* ]] && INSTALL_GNOME=true
INSTALL_MATE=false;     [[ "$_DE_SEL" == *"5"* ]] && INSTALL_MATE=true
_DE_NAMES=""
$INSTALL_KDE      && _DE_NAMES="$_DE_NAMES KDE"
$INSTALL_XFCE     && _DE_NAMES="$_DE_NAMES XFCE4"
$INSTALL_CINNAMON && _DE_NAMES="$_DE_NAMES Cinnamon"
$INSTALL_GNOME    && _DE_NAMES="$_DE_NAMES GNOME"
$INSTALL_MATE     && _DE_NAMES="$_DE_NAMES MATE"
echo -e "  → DEs retenus :${GREEN}${_DE_NAMES}${NC}"

# ── Sélection AUR Helper ─────────────────────────────────
echo ""
echo -e "${BOLD}AUR Helper — requis pour certains paquets :${NC}"
echo -e "  [A1] yay     — Go, le plus populaire     ${GREEN}✓${NC}"
echo -e "  [A2] paru    — Rust, fork de yay, rapide"
echo -e "  [A3] trizen  — Perl, léger"
echo -e "  [A0] Aucun   — ${YELLOW}⚠️  les paquets marqués (AUR) ne seront pas installés${NC}"
echo ""
read -rp "$(echo -e "${YELLOW}AUR Helper${NC} [A1]: ")" _AUR_HELPER_SEL
_AUR_HELPER_SEL="${_AUR_HELPER_SEL:-A1}"
AUR_HELPER="none"
case "${_AUR_HELPER_SEL^^}" in
    A1) AUR_HELPER="yay" ;;
    A2) AUR_HELPER="paru" ;;
    A3) AUR_HELPER="trizen" ;;
    A0) AUR_HELPER="none" ;;
    *)  AUR_HELPER="yay" ;;
esac
echo -e "  → AUR Helper retenu : ${GREEN}${AUR_HELPER}${NC}"
[[ "$AUR_HELPER" == "none" ]] && echo -e "  ${RED}⚠️  Sans AUR helper : Brave, Heroic, Bottles, Discord, Timeshift, VSCode ne seront pas installés${NC}"

# ── Sélection des paquets ─────────────────────────────────
echo ""
echo -e "${BOLD}Paquets — sélectionner par catégorie (numéros séparés par espaces) :${NC}"
echo -e "${YELLOW}[0] Tout sélectionner${NC}"
echo ""
echo -e "${BLUE}── Navigateurs ─────────────────────────────${NC}"
echo -e "  [1]  Firefox          ${GREEN}✓${NC}"
echo -e "  [2]  Chromium"
echo -e "  [3]  Brave            ${YELLOW}(AUR — nécessite AUR helper)${NC}"
echo ""
echo -e "${BLUE}── Gaming ──────────────────────────────────${NC}"
echo -e "  [4]  Steam            ${GREEN}✓${NC}"
echo -e "  [5]  Lutris           ${GREEN}✓${NC}"
echo -e "  [6]  Heroic           ${YELLOW}(AUR — Epic/GOG)${NC}"
echo -e "  [7]  GameMode         ${GREEN}✓${NC}"
echo -e "  [8]  MangoHud         ${GREEN}✓${NC}"
echo -e "  [9]  Bottles          ${YELLOW}(AUR — Wine manager)${NC}"
echo -e "  [10] Discord          ${YELLOW}(AUR)${NC}"
echo ""
echo -e "${BLUE}── Streaming / Création ────────────────────${NC}"
echo -e "  [11] OBS Studio       ${GREEN}✓${NC}"
echo -e "  [12] Kdenlive"
echo -e "  [13] Blender"
echo -e "  [14] GIMP"
echo -e "  [15] Inkscape"
echo -e "  [16] Audacity"
echo ""
echo -e "${BLUE}── Productivité ────────────────────────────${NC}"
echo -e "  [17] LibreOffice"
echo -e "  [18] Thunderbird"
echo -e "  [19] KeePassXC"
echo -e "  [20] Flameshot"
echo -e "  [21] Timeshift        ${YELLOW}(AUR)${NC}"
echo -e "  [22] Gnome Disk Utility ${GREEN}✓${NC}"
echo ""
echo -e "${BLUE}── Développement ───────────────────────────${NC}"
echo -e "  [23] VSCode           ${YELLOW}(AUR)${NC}"
echo -e "  [24] Neovim"
echo -e "  [25] Docker"
echo ""
echo -e "${BLUE}── Réseau / Utilitaires ────────────────────${NC}"
echo -e "  [26] VLC              ${GREEN}✓${NC}"
echo -e "  [27] qBittorrent"
echo -e "  [28] FileZilla"
echo ""
[[ "$AUR_HELPER" == "none" ]] && echo -e "${YELLOW}⚠️  AUR helper absent — les paquets [3][6][9][10][21][23] seront ignorés même si sélectionnés${NC}\n"
echo ""
read -rp "$(echo -e "${YELLOW}Sélection${NC} [1 4 5 7 8 11 22 26]: ")" _PKG_SEL
_PKG_SEL="${_PKG_SEL:-1 4 5 7 8 11 22 26}"
[[ "$_PKG_SEL" == *"0"* ]] && _PKG_SEL="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28"

# Normaliser : ajouter espaces autour de chaque token pour éviter les conflits (1 vs 21, 3 vs 13/23...)
_PKG_SEL=" ${_PKG_SEL} "

# Désactiver les paquets AUR si pas d'AUR helper
if [[ "$AUR_HELPER" == "none" ]]; then
    for _n in 3 6 9 10 21 23; do
        _PKG_SEL="${_PKG_SEL/ $_n / }"
    done
fi

# Fonction helper de détection
_has_pkg() { [[ " $_PKG_SEL " == *" $1 "* ]]; }

# Navigateurs
PKG_FIREFOX=false;    _has_pkg 1  && PKG_FIREFOX=true
PKG_CHROMIUM=false;   _has_pkg 2  && PKG_CHROMIUM=true
PKG_BRAVE=false;      _has_pkg 3  && PKG_BRAVE=true
# Gaming
PKG_STEAM=false;      _has_pkg 4  && PKG_STEAM=true
PKG_LUTRIS=false;     _has_pkg 5  && PKG_LUTRIS=true
PKG_HEROIC=false;     _has_pkg 6  && PKG_HEROIC=true
PKG_GAMEMODE=false;   _has_pkg 7  && PKG_GAMEMODE=true
PKG_MANGOHUD=false;   _has_pkg 8  && PKG_MANGOHUD=true
PKG_BOTTLES=false;    _has_pkg 9  && PKG_BOTTLES=true
PKG_DISCORD=false;    _has_pkg 10 && PKG_DISCORD=true
# Streaming
PKG_OBS=false;        _has_pkg 11 && PKG_OBS=true
PKG_KDENLIVE=false;   _has_pkg 12 && PKG_KDENLIVE=true
PKG_BLENDER=false;    _has_pkg 13 && PKG_BLENDER=true
PKG_GIMP=false;       _has_pkg 14 && PKG_GIMP=true
PKG_INKSCAPE=false;   _has_pkg 15 && PKG_INKSCAPE=true
PKG_AUDACITY=false;   _has_pkg 16 && PKG_AUDACITY=true
# Productivité
PKG_LIBREOFFICE=false; _has_pkg 17 && PKG_LIBREOFFICE=true
PKG_THUNDERBIRD=false; _has_pkg 18 && PKG_THUNDERBIRD=true
PKG_KEEPASSXC=false;   _has_pkg 19 && PKG_KEEPASSXC=true
PKG_FLAMESHOT=false;   _has_pkg 20 && PKG_FLAMESHOT=true
PKG_TIMESHIFT=false;   _has_pkg 21 && PKG_TIMESHIFT=true
PKG_GNOME_DISK=false;  _has_pkg 22 && PKG_GNOME_DISK=true
# Développement
PKG_VSCODE=false;     _has_pkg 23 && PKG_VSCODE=true
PKG_NEOVIM=false;     _has_pkg 24 && PKG_NEOVIM=true
PKG_DOCKER=false;     _has_pkg 25 && PKG_DOCKER=true
# Réseau
PKG_VLC=false;        _has_pkg 26 && PKG_VLC=true
PKG_QBITTORRENT=false; _has_pkg 27 && PKG_QBITTORRENT=true
PKG_FILEZILLA=false;   _has_pkg 28 && PKG_FILEZILLA=true

echo ""
echo -e "  → Paquets retenus : ${GREEN}${_PKG_SEL}${NC}"

echo ""
echo -e "${BOLD}Configuration retenue :${NC}"
echo -e "  Config   : ${GREEN}${_CONFIG_LABELS[$CONFIG]}${NC}"
echo -e "  Disque   : ${GREEN}$DISK${NC}"
echo -e "  Hostname : ${GREEN}$HOSTNAME${NC}"
echo -e "  User     : ${GREEN}$USERNAME${NC}"
echo -e "  Timezone : ${GREEN}$TIMEZONE${NC}"
echo -e "  Locale   : ${GREEN}$LOCALE${NC}"
echo -e "  Clavier  : ${GREEN}$KEYMAP${NC}"
echo ""

# ══════════════════════════════════════════════════════════
#  VÉRIFICATIONS
# ══════════════════════════════════════════════════════════
banner "VÉRIFICATIONS"

[[ -d /sys/firmware/efi ]] || error "Non démarré en mode UEFI — vérifie le BIOS."
info "Mode UEFI confirmé"

ping -c1 -W3 archlinux.org &>/dev/null || error "Pas de connexion internet."
info "Connexion internet OK"

[[ -b "$DISK" ]] || error "Disque $DISK introuvable."
info "Disque $DISK trouvé"

# ══════════════════════════════════════════════════════════
#  MOTS DE PASSE
# ══════════════════════════════════════════════════════════
banner "MOTS DE PASSE"

echo -e "${YELLOW}→ Mot de passe root :${NC}"
read -rsp "  Mot de passe : " ROOT_PASS; echo
read -rsp "  Confirmer   : " ROOT_PASS2; echo
[[ "$ROOT_PASS" == "$ROOT_PASS2" ]] || error "Mots de passe root différents."
warn_weak_password "root" "$ROOT_PASS"

echo -e "\n${YELLOW}→ Mot de passe utilisateur ($USERNAME) :${NC}"
read -rsp "  Mot de passe : " USER_PASS; echo
read -rsp "  Confirmer   : " USER_PASS2; echo
[[ "$USER_PASS" == "$USER_PASS2" ]] || error "Mots de passe utilisateur différents."
warn_weak_password "$USERNAME" "$USER_PASS"

# ══════════════════════════════════════════════════════════
#  CONFIRMATION FINALE
# ══════════════════════════════════════════════════════════
banner "CONFIRMATION"
echo -e "${RED}${BOLD}⚠️  ATTENTION : $DISK va être entièrement effacé !${NC}"
ask "Lancer l'installation ?" "n" || error "Installation annulée."

# ══════════════════════════════════════════════════════════
#  HORLOGE
# ══════════════════════════════════════════════════════════
banner "HORLOGE"
timedatectl set-ntp true
info "Synchronisation NTP activée"

# ══════════════════════════════════════════════════════════
#  DÉMONTAGE PRÉALABLE
# ══════════════════════════════════════════════════════════
banner "DÉMONTAGE PRÉALABLE"
if mountpoint -q /mnt; then
    warn "/mnt est monté — démontage..."
    umount -R /mnt &>/dev/null || umount -R -l /mnt &>/dev/null || true
fi
for PART in $(lsblk -ln -o NAME,MOUNTPOINT "$DISK" 2>/dev/null | awk '$2!="" {print "/dev/"$1}'); do
    umount -l "$PART" 2>/dev/null || true
done
success "Démontage terminé"

# ══════════════════════════════════════════════════════════
#  PARTITIONNEMENT
# ══════════════════════════════════════════════════════════
banner "PARTITIONNEMENT"
info "Effacement et partitionnement de $DISK..."
sgdisk -Z "$DISK" &>/dev/null || true
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"  "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"
success "Partitions créées — EFI=$EFI_PART ROOT=$ROOT_PART"

# ══════════════════════════════════════════════════════════
#  FORMATAGE
# ══════════════════════════════════════════════════════════
banner "FORMATAGE"
mkfs.fat -F32 "$EFI_PART"
success "EFI formaté en FAT32"
mkfs.ext4 -F "$ROOT_PART"
success "ROOT formaté en ext4"

# ══════════════════════════════════════════════════════════
#  MONTAGE
# ══════════════════════════════════════════════════════════
banner "MONTAGE"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
success "Partitions montées"

# ══════════════════════════════════════════════════════════
#  MIROIRS
# ══════════════════════════════════════════════════════════
banner "MIROIRS"
info "Sélection du miroir le plus rapide (France)..."
reflector --country France --age 12 --protocol https --sort rate \
    --timeout 5 --latest 20 \
    --save /etc/pacman.d/mirrorlist &>/dev/null \
    || warn "reflector échoué — miroirs par défaut conservés"
SELECTED_MIRROR=$(grep "^Server" /etc/pacman.d/mirrorlist 2>/dev/null | head -1 | sed 's/Server = //') || true
SELECTED_MIRROR="${SELECTED_MIRROR:-miroir par défaut}"
success "Miroir : ${SELECTED_MIRROR}"

# ══════════════════════════════════════════════════════════
#  PACSTRAP — BASE SYSTÈME
# ══════════════════════════════════════════════════════════
banner "PACSTRAP — BASE SYSTÈME"
info "Installation du système de base..."

_UCODE_PKG=""
if ! $_IS_VM; then
    [[ "$_CPU" == "intel" ]] && _UCODE_PKG="intel-ucode" || _UCODE_PKG="amd-ucode"
fi

pacstrap -K /mnt \
    base base-devel ${KERNELS} linux-firmware \
    ${_UCODE_PKG} \
    networkmanager \
    grub efibootmgr \
    nano vim git curl wget \
    gptfdisk \
    --disable-download-timeout
success "Base système installée"

# ══════════════════════════════════════════════════════════
#  FSTAB
# ══════════════════════════════════════════════════════════
banner "FSTAB"
genfstab -U /mnt >> /mnt/etc/fstab
success "fstab généré"

# ══════════════════════════════════════════════════════════
#  CONFIGURATION (CHROOT)
# ══════════════════════════════════════════════════════════
banner "CONFIGURATION (CHROOT)"
info "Entrée dans l'environnement chroot..."

arch-chroot /mnt /bin/bash << CHROOT_SCRIPT
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "\n\${BLUE}[INFO]\${NC} \$1"; }
success() { echo -e "\${GREEN}[OK]\${NC} \$1"; }
warn()    { echo -e "\${YELLOW}[WARN]\${NC} \$1"; }
banner()  { echo -e "\n\${BOLD}══ \$1 ══\${NC}"; }

# Variables passées depuis le script principal
TIMEZONE="${TIMEZONE}"
LOCALE="${LOCALE}"
KEYMAP="${KEYMAP}"
HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
ROOT_PASS="${ROOT_PASS}"
USER_PASS="${USER_PASS}"
CONFIG="${CONFIG}"
_IS_VM="${_IS_VM}"
_NEED_NVIDIA="${_NEED_NVIDIA}"
_NEED_AMD_GPU="${_NEED_AMD_GPU}"
_OPTIMUS="${_OPTIMUS}"
_CPU="${_CPU}"
AUR_HELPER="${AUR_HELPER}"
INSTALL_KDE="${INSTALL_KDE}"
INSTALL_XFCE="${INSTALL_XFCE}"
INSTALL_CINNAMON="${INSTALL_CINNAMON}"
INSTALL_GNOME="${INSTALL_GNOME}"
INSTALL_MATE="${INSTALL_MATE}"
PKG_FIREFOX="${PKG_FIREFOX}"
PKG_CHROMIUM="${PKG_CHROMIUM}"
PKG_BRAVE="${PKG_BRAVE}"
PKG_STEAM="${PKG_STEAM}"
PKG_LUTRIS="${PKG_LUTRIS}"
PKG_HEROIC="${PKG_HEROIC}"
PKG_GAMEMODE="${PKG_GAMEMODE}"
PKG_MANGOHUD="${PKG_MANGOHUD}"
PKG_BOTTLES="${PKG_BOTTLES}"
PKG_DISCORD="${PKG_DISCORD}"
PKG_OBS="${PKG_OBS}"
PKG_KDENLIVE="${PKG_KDENLIVE}"
PKG_BLENDER="${PKG_BLENDER}"
PKG_GIMP="${PKG_GIMP}"
PKG_INKSCAPE="${PKG_INKSCAPE}"
PKG_AUDACITY="${PKG_AUDACITY}"
PKG_LIBREOFFICE="${PKG_LIBREOFFICE}"
PKG_THUNDERBIRD="${PKG_THUNDERBIRD}"
PKG_KEEPASSXC="${PKG_KEEPASSXC}"
PKG_FLAMESHOT="${PKG_FLAMESHOT}"
PKG_TIMESHIFT="${PKG_TIMESHIFT}"
PKG_GNOME_DISK="${PKG_GNOME_DISK}"
PKG_VSCODE="${PKG_VSCODE}"
PKG_NEOVIM="${PKG_NEOVIM}"
PKG_DOCKER="${PKG_DOCKER}"
PKG_VLC="${PKG_VLC}"
PKG_QBITTORRENT="${PKG_QBITTORRENT}"
PKG_FILEZILLA="${PKG_FILEZILLA}"

# ── Timezone ──────────────────────────────────────────────
banner "TIMEZONE"
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
success "Timezone : ${TIMEZONE}"

# ── Locale ────────────────────────────────────────────────
banner "LOCALE"
sed -i 's/^#${LOCALE}/${LOCALE}/' /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
success "Locale : ${LOCALE} — Clavier : ${KEYMAP}"

# ── Hostname ──────────────────────────────────────────────
banner "HOSTNAME"
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
success "Hostname : ${HOSTNAME}"

# ── Utilisateurs ──────────────────────────────────────────
banner "UTILISATEURS"
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
success "Utilisateurs créés"

# ── Clavier X11 ───────────────────────────────────────────
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${KEYMAP}"
    Option "XkbModel" "pc105"
EndSection
EOF
success "Clavier X11 configuré"

# ── GRUB ──────────────────────────────────────────────────
banner "GRUB"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3600/' /etc/default/grub
sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
sed -i 's/^#\?GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080x32/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
success "GRUB installé"

# ── Multilib ──────────────────────────────────────────────
banner "MULTILIB"
sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf
pacman -Sy --noconfirm
success "Dépôt multilib activé"

# ── Drivers GPU ───────────────────────────────────────────
banner "DRIVERS GPU"
CONFIG="${CONFIG}"
_IS_VM="${_IS_VM}"
_NEED_NVIDIA="${_NEED_NVIDIA}"
_NEED_AMD_GPU="${_NEED_AMD_GPU}"
_OPTIMUS="${_OPTIMUS}"

if [[ "\$_IS_VM" == "true" ]]; then
    info "Drivers VMware (mesa + xf86-input-vmmouse)..."
    pacman -S --noconfirm \
        mesa xf86-input-vmmouse vulkan-icd-loader \
        --disable-download-timeout
    # open-vm-tools
    pacman -S --noconfirm \
        open-vm-tools xf86-video-vmware \
        --disable-download-timeout 2>/dev/null || \
    pacman -S --noconfirm \
        open-vm-tools \
        --disable-download-timeout
    success "Drivers VMware installés"

elif [[ "\$_NEED_NVIDIA" == "true" && "\$_NEED_AMD_GPU" == "true" ]]; then
    info "Drivers Optimus (AMD iGPU + NVIDIA dGPU)..."
    pacman -S --noconfirm \
        mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu \
        --disable-download-timeout
    pacman -S --noconfirm \
        nvidia nvidia-utils nvidia-settings \
        lib32-nvidia-utils lib32-mesa \
        --disable-download-timeout
    pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader \
        --disable-download-timeout
    echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
    sed -i 's/^MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    # switcheroo-control pour Optimus
    pacman -S --noconfirm switcheroo-control --disable-download-timeout
    success "Drivers Optimus installés"

elif [[ "\$_NEED_NVIDIA" == "true" ]]; then
    info "Drivers NVIDIA (dGPU seul)..."
    pacman -S --noconfirm \
        nvidia nvidia-utils nvidia-settings \
        lib32-nvidia-utils lib32-mesa \
        --disable-download-timeout
    pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader \
        --disable-download-timeout
    echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
    sed -i 's/^MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    success "Drivers NVIDIA installés"

elif [[ "\$_NEED_AMD_GPU" == "true" ]]; then
    info "Drivers AMD GPU..."
    pacman -S --noconfirm \
        mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu \
        lib32-mesa lib32-vulkan-radeon \
        --disable-download-timeout
    pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader \
        --disable-download-timeout
    success "Drivers AMD GPU installés"

else
    info "Drivers Intel iGPU..."
    pacman -S --noconfirm \
        mesa vulkan-intel intel-media-driver \
        lib32-mesa lib32-vulkan-intel \
        --disable-download-timeout
    pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader \
        --disable-download-timeout
    success "Drivers Intel installés"
fi

# ── Pipewire ──────────────────────────────────────────────
banner "PIPEWIRE"
pacman -S --noconfirm \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack \
    wireplumber \
    --disable-download-timeout
success "Pipewire installé"

# ── KDE Plasma ────────────────────────────────────────────
if [[ "${INSTALL_KDE}" == "true" ]]; then
    banner "KDE PLASMA"
    pacman -S --noconfirm \
        plasma-meta sddm \
        dolphin konsole kate ark gwenview okular spectacle yakuake \
        --disable-download-timeout
    success "KDE Plasma installé"
fi

# ── XFCE4 ─────────────────────────────────────────────────
if [[ "${INSTALL_XFCE}" == "true" ]]; then
    banner "XFCE4"
    pacman -S --noconfirm \
        xfce4 xfce4-goodies \
        --disable-download-timeout
    success "XFCE4 installé"
fi

# ── Cinnamon ──────────────────────────────────────────────
if [[ "${INSTALL_CINNAMON}" == "true" ]]; then
    banner "CINNAMON"
    pacman -S --noconfirm \
        cinnamon \
        --disable-download-timeout
    success "Cinnamon installé"
fi

# ── GNOME ─────────────────────────────────────────────────
if [[ "${INSTALL_GNOME}" == "true" ]]; then
    banner "GNOME"
    pacman -S --noconfirm \
        gnome gnome-extra \
        --disable-download-timeout
    success "GNOME installé"
fi

# ── MATE ──────────────────────────────────────────────────
if [[ "${INSTALL_MATE}" == "true" ]]; then
    banner "MATE"
    pacman -S --noconfirm \
        mate mate-extra \
        --disable-download-timeout
    success "MATE installé"
fi

# Gestionnaire de connexion — SDDM si KDE, sinon lightdm
if [[ "${INSTALL_KDE}" == "false" ]]; then
    pacman -S --noconfirm lightdm lightdm-gtk-greeter --disable-download-timeout
    systemctl enable lightdm 2>/dev/null || true
fi

# ── AUR Helper ────────────────────────────────────────────
AUR_HELPER="${AUR_HELPER}"
if [[ "$AUR_HELPER" != "none" ]]; then
    banner "AUR HELPER — ${AUR_HELPER}"
    pacman -S --noconfirm --needed go git base-devel --disable-download-timeout
    cd /tmp
    git clone "https://aur.archlinux.org/${AUR_HELPER}.git"
    chmod 777 "/tmp/${AUR_HELPER}"
    cd "/tmp/${AUR_HELPER}"
    sudo -u "${USERNAME}" makepkg -si --noconfirm
    cd /
    rm -rf "/tmp/${AUR_HELPER}"
    success "${AUR_HELPER} installé"
fi

# ── Paquets utilitaires ───────────────────────────────────
banner "LOGICIELS SUPPLÉMENTAIRES"
_PACMAN_PKGS="htop fastfetch"
_AUR_PKGS=""

# Navigateurs
[[ "${PKG_FIREFOX}"     == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS firefox"
[[ "${PKG_CHROMIUM}"    == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS chromium"
[[ "${PKG_BRAVE}"       == "true" ]] && _AUR_PKGS="$_AUR_PKGS brave-bin"
# Gaming
[[ "${PKG_STEAM}"       == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS steam"
[[ "${PKG_LUTRIS}"      == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS lutris"
[[ "${PKG_HEROIC}"      == "true" ]] && _AUR_PKGS="$_AUR_PKGS heroic-games-launcher-bin"
[[ "${PKG_GAMEMODE}"    == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS gamemode lib32-gamemode"
[[ "${PKG_MANGOHUD}"    == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS mangohud lib32-mangohud"
[[ "${PKG_BOTTLES}"     == "true" ]] && _AUR_PKGS="$_AUR_PKGS bottles"
[[ "${PKG_DISCORD}"     == "true" ]] && _AUR_PKGS="$_AUR_PKGS discord"
# Streaming / Création
[[ "${PKG_OBS}"         == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS obs-studio"
[[ "${PKG_KDENLIVE}"    == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS kdenlive"
[[ "${PKG_BLENDER}"     == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS blender"
[[ "${PKG_GIMP}"        == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS gimp"
[[ "${PKG_INKSCAPE}"    == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS inkscape"
[[ "${PKG_AUDACITY}"    == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS audacity"
# Productivité
[[ "${PKG_LIBREOFFICE}" == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS libreoffice-fresh"
[[ "${PKG_THUNDERBIRD}" == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS thunderbird"
[[ "${PKG_KEEPASSXC}"   == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS keepassxc"
[[ "${PKG_FLAMESHOT}"   == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS flameshot"
[[ "${PKG_TIMESHIFT}"   == "true" ]] && _AUR_PKGS="$_AUR_PKGS timeshift"
[[ "${PKG_GNOME_DISK}"  == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS gnome-disk-utility"
# Développement
[[ "${PKG_NEOVIM}"      == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS neovim"
[[ "${PKG_DOCKER}"      == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS docker docker-compose"
[[ "${PKG_VSCODE}"      == "true" ]] && _AUR_PKGS="$_AUR_PKGS visual-studio-code-bin"
# Réseau
[[ "${PKG_VLC}"         == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS vlc"
[[ "${PKG_QBITTORRENT}" == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS qbittorrent"
[[ "${PKG_FILEZILLA}"   == "true" ]] && _PACMAN_PKGS="$_PACMAN_PKGS filezilla"

# Installer paquets pacman
pacman -S --noconfirm ${_PACMAN_PKGS} --disable-download-timeout
success "Logiciels pacman installés"

# Activer Docker si installé
[[ "${PKG_DOCKER}" == "true" ]] && systemctl enable docker 2>/dev/null || true

# Installer paquets AUR avec le helper choisi
if [[ -n "${_AUR_PKGS## }" && "$AUR_HELPER" != "none" ]]; then
    info "Installation des paquets AUR via ${AUR_HELPER}..."
    sudo -u "${USERNAME}" ${AUR_HELPER} -S --noconfirm --mflags "--nocheck" ${_AUR_PKGS}
    success "Paquets AUR installés"
fi

# ── SDDM ──────────────────────────────────────────────────
banner "SDDM"
mkdir -p /etc/systemd/system/sddm.service.d
cat > /etc/systemd/system/sddm.service.d/locale.conf << EOF
[Service]
Environment=LANG=en_US.UTF-8
EOF
# Fond d'écran SDDM
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf.user << EOF
[Theme]
Current=breeze
CursorTheme=breeze_cursors
Background=/usr/share/wallpapers/Next/contents/images_dark/5120x2880.png
EOF
success "SDDM configuré"

# ── Clavier KDE / XFCE ───────────────────────────────────
mkdir -p /home/${USERNAME}/.config
cat > /home/${USERNAME}/.config/kxkbrc << EOF
[Layout]
DisplayNames=
LayoutList=${KEYMAP}
Model=pc105
Use=true
VariantList=
EOF
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
success "Clavier KDE configuré"

# ── Services ──────────────────────────────────────────────
banner "SERVICES"
systemctl enable NetworkManager
systemctl enable sddm

if [[ "${_IS_VM}" == "true" ]]; then
    systemctl enable vmtoolsd
    systemctl enable vmware-vmblock-fuse
    success "Services activés : NetworkManager, SDDM, vmtoolsd, vmware-vmblock-fuse"
elif [[ "${_OPTIMUS}" == "true" ]]; then
    systemctl enable switcheroo-control
    success "Services activés : NetworkManager, SDDM, switcheroo-control"
else
    success "Services activés : NetworkManager, SDDM"
fi

# ── Swapfile ──────────────────────────────────────────────
banner "SWAPFILE"
dd if=/dev/zero of=/swapfile bs=1M count=8192 status=progress
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
success "Swapfile 8 Go créé"

CHROOT_SCRIPT

success "Configuration chroot terminée"

# ══════════════════════════════════════════════════════════
#  DÉMONTAGE
# ══════════════════════════════════════════════════════════
banner "DÉMONTAGE"
sync
umount -R -l /mnt
success "Partitions démontées"

# ══════════════════════════════════════════════════════════
#  FIN
# ══════════════════════════════════════════════════════════
echo -e "\n${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           ✅ INSTALLATION TERMINÉE !                        ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Config : %-50s ║\n" "${_CONFIG_LABELS[$CONFIG]}"
printf "║  Disque : %-50s ║\n" "$DISK"
printf "║  User   : %-50s ║\n" "$USERNAME @ $HOSTNAME"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  1. Retire la clé USB                                       ║"
echo "║  2. Redémarre : reboot                                      ║"
echo "║  3. Lance le script post-install (script 2) dans KDE        ║"
if [[ "$_OPTIMUS" == "true" ]]; then
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  GPU Optimus — envycontrol (via script 2) :                 ║"
echo "║    sudo envycontrol -s hybrid   → mode recommandé           ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
