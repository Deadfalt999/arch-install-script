#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║         ARCH LINUX — SCRIPT D'INSTALLATION UNIFIÉ           ║
# ║  Laptop AMD/Intel + NVIDIA · Desktop AMD/Intel · VMware     ║
# ║  Détection automatique de la configuration matérielle       ║
# ╚══════════════════════════════════════════════════════════════╝
# Usage : bash 1-install.sh
# ⚠️  Ce script va EFFACER ENTIÈREMENT le disque cible !

set -uo pipefail

# ══════════════════════════════════════════════════════════
#  LOGGING — tout l'output est capturé dans ais.log
#  NOTE: on utilise un pipe tee, ce qui casse isatty() pour
#  pacman. Le fix TTY est appliqué via `script` pour pacstrap
#  et via TERM + pacman.conf pour les appels dans le chroot.
# ══════════════════════════════════════════════════════════
LOG_FILE="/root/ais.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "═══════════════════════════════════════════════════"
echo " Installation démarrée le $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════"

trap 's=$?; echo -e "\n❌ Erreur ligne $LINENO : $BASH_COMMAND\n"; exit $s' ERR

# ══════════════════════════════════════════════════════════
#  COULEURS & FONCTIONS CONSOLE
# ══════════════════════════════════════════════════════════
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "\n${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }
banner()  { echo -e "\n${BOLD}══ $1 ══${NC}"; }

# ══════════════════════════════════════════════════════════
#  ÉTAPE 0 — PRÉ-REQUIS (avant toute installation)
#  Vérifications et NTP en mode texte pur, sans dialog,
#  car le réseau n'est pas encore garanti opérationnel.
# ══════════════════════════════════════════════════════════
banner "PRÉ-REQUIS"

[[ -d /sys/firmware/efi ]] || error "Non démarré en mode UEFI — vérifie le BIOS."
info "Mode UEFI confirmé"

info "Vérification de la connexion internet..."
if ! ping -c1 -W5 archlinux.org &>/dev/null; then
    error "Pas de connexion internet. Configure le réseau (ex: iwctl, dhcpcd) puis relance le script."
fi
success "Connexion internet OK"

banner "HORLOGE"
timedatectl set-ntp true
info "Synchronisation NTP activée"
for _i in $(seq 1 15); do
    timedatectl status 2>/dev/null | grep -q "synchronized: yes" && break
    sleep 1
done
timedatectl status 2>/dev/null | grep -q "synchronized: yes" \
    && success "Heure synchronisée" \
    || warn "NTP pas encore confirmé — on continue"

# ══════════════════════════════════════════════════════════
#  INSTALLATION DE DIALOG
# ══════════════════════════════════════════════════════════
banner "INSTALLATION DE DIALOG"
if ! command -v dialog &>/dev/null; then
    info "Installation de dialog via pacman..."
    pacman -Sy --noconfirm dialog
    success "dialog installé"
else
    success "dialog déjà disponible"
fi

# ══════════════════════════════════════════════════════════
#  INITIALISATION DE L'INTERFACE TUI (dialog)
# ══════════════════════════════════════════════════════════

_ROWS=$(tput lines 2>/dev/null || echo 30)
_COLS=$(tput cols  2>/dev/null || echo 80)
DH=$(( _ROWS - 4 )); DW=$(( _COLS - 4 ))
[[ $DH -lt 20 ]] && DH=20
[[ $DW -lt 60 ]] && DW=60

_TMP=$(mktemp)
_LOG=$(mktemp)    # Log file for all install output
trap 'rm -f "$_TMP" "$_LOG"; s=$?; [[ $s -ne 0 ]] && echo -e "\n❌ Erreur ligne $LINENO : $BASH_COMMAND\n"; exit $s' EXIT ERR

error() { dialog --title "❌ Erreur fatale" --msgbox "$1" 8 60 >/dev/tty; clear; echo -e "${RED}[ERREUR]${NC} $1"; exit 1; }
banner()  { echo -e "\n${BOLD}══ $1 ══${NC}"; }

# ── Helpers dialog ─────────────────────────────────────────
d_input() {
    dialog --clear --title "$1" \
           --inputbox "$2" 10 "$DW" "$3" \
           2>"$_TMP" >/dev/tty
    local rc=$?; [[ $rc -ne 0 ]] && { clear; error "Installation annulée."; }
    cat "$_TMP"
}

d_password() {
    dialog --clear --title "$1" \
           --insecure --passwordbox "$2" 10 "$DW" \
           2>"$_TMP" >/dev/tty
    local rc=$?; [[ $rc -ne 0 ]] && { clear; error "Installation annulée."; }
    cat "$_TMP"
}

d_menu() {
    local title="$1" label="$2"; shift 2
    dialog --clear --title "$title" \
           --menu "$label" "$DH" "$DW" $(( $# / 2 )) "$@" \
           2>"$_TMP" >/dev/tty
    local rc=$?; [[ $rc -ne 0 ]] && { clear; error "Installation annulée."; }
    cat "$_TMP"
}

d_checklist() {
    local title="$1" label="$2"; shift 2
    dialog --clear --title "$title" \
           --checklist "$label" "$DH" "$DW" $(( $# / 3 )) "$@" \
           2>"$_TMP" >/dev/tty
    local rc=$?; [[ $rc -ne 0 ]] && { clear; error "Installation annulée."; }
    cat "$_TMP" | tr -d '"'
}

d_yesno() {
    dialog --clear --title "$1" --yesno "$2" 10 "$DW" >/dev/tty
}

d_msgbox() {
    dialog --clear --title "$1" --msgbox "$2" 12 "$DW" >/dev/tty
}

# ── Progress helpers ───────────────────────────────────────

# d_progress_box <title> <cmd...>
# Streams live command output into a scrollable dialog progressbox.
# On failure, shows the last 20 lines in an error box.
d_progress_box() {
    local title="$1"; shift
    local cmd_log; cmd_log=$(mktemp)
    (
        "$@" 2>&1 | tee "$cmd_log" \
        | dialog --title "$title" \
                 --progressbox "Sortie en direct — patientez..." \
                 $(( DH + 2 )) "$DW" >/dev/tty
    )
    local pipe_statuses=("${PIPESTATUS[@]}")
    local cmd_rc="${pipe_statuses[0]}"
    if [[ "$cmd_rc" -ne 0 ]]; then
        local tail_output; tail_output=$(tail -20 "$cmd_log")
        rm -f "$cmd_log"
        error "La commande a échoué (code $cmd_rc) :\n\n$title\n\nDernières lignes :\n$tail_output"
    fi
    cat "$cmd_log" >> "$_LOG"
    rm -f "$cmd_log"
}

# d_run_gauge <pct> <title> <label> <cmd...>
# Runs a command in background while showing a static gauge at pct%.
d_run_gauge() {
    local pct="$1" title="$2" label="$3"; shift 3
    local cmd_log; cmd_log=$(mktemp)
    (
        "$@" >"$cmd_log" 2>&1
        echo $? > "${cmd_log}.rc"
    ) &
    local bg_pid=$!
    while kill -0 "$bg_pid" 2>/dev/null; do
        echo "$pct"
        sleep 0.3
    done | dialog --title "$title" \
                  --gauge "$label" 8 "$DW" 0 >/dev/tty
    wait "$bg_pid" 2>/dev/null || true
    local rc=0
    [[ -f "${cmd_log}.rc" ]] && rc=$(cat "${cmd_log}.rc")
    if [[ "$rc" -ne 0 ]]; then
        local tail_output; tail_output=$(tail -20 "$cmd_log")
        rm -f "$cmd_log" "${cmd_log}.rc"
        error "La commande a échoué (code $rc) :\n\n$title — $label\n\nDernières lignes :\n$tail_output"
    fi
    cat "$cmd_log" >> "$_LOG"
    rm -f "$cmd_log" "${cmd_log}.rc"
}

# pacman_gauge <title> <pkg1> [pkg2 ...]
# Pre-counts packages with -Sp, then installs while parsing pacman's
# "(N/N) Downloading/Installing pkg" lines to drive dialog --gauge.
# The gauge label updates live: "Downloading linux (3/42)"
pacman_gauge() {
    local title="$1"; shift
    local pkgs=("$@")
    local cmd_log; cmd_log=$(mktemp)
    local rc_file; rc_file=$(mktemp)

    (
        stdbuf -oL pacman -S --noconfirm --disable-download-timeout "${pkgs[@]}" \
            2>&1 \
        | stdbuf -oL tee "$cmd_log" \
        | stdbuf -oL awk '
            /^\(([0-9]+)\/([0-9]+)\)/ {
                match($0, /^\(([0-9]+)\/([0-9]+)\)[[:space:]]+([A-Za-z]+)[[:space:]]+([^[:space:]]+)/, a)
                n     = a[1]+0
                total = a[2]+0
                action = a[3]
                pkg   = a[4]
                if (total > 0) pct = int(n * 100 / total)
                else           pct = 0
                printf "XXX\n%d\n%-12s %s  (%d/%d)\nXXX\n", pct, action, pkg, n, total
                fflush()
            }
            END { print "100" }
        ' \
        | dialog --title "$title" \
                 --gauge "Initialisation..." 8 "$DW" 0 >/dev/tty
        echo "${PIPESTATUS[0]}" > "$rc_file"
    )
    local rc; rc=$(cat "$rc_file"); rm -f "$rc_file"

    if [[ "$rc" -ne 0 ]]; then
        local tail_output; tail_output=$(tail -20 "$cmd_log")
        rm -f "$cmd_log"
        error "pacman a échoué (code $rc) :\n\n$title\n\nDernières lignes :\n$tail_output"
    fi
    cat "$cmd_log" >> "$_LOG"
    rm -f "$cmd_log"
}

# pacstrap_gauge <title> <mountpoint> <pkg1> [pkg2 ...]
# Counts expected downloads with `pacman -Sp` on the host, then runs
# pacstrap and tracks "Downloading" lines to drive dialog --gauge.
# Percentage = finished downloads / total downloads.
pacstrap_gauge() {
    local title="$1" mnt="$2"; shift 2
    local pkgs=("$@")
    local cmd_log; cmd_log=$(mktemp)
    local rc_file; rc_file=$(mktemp)

    # pacman -Sp resolves the full dependency tree and prints one URL per line.
    # We count lines to get total_dl — this is the actual number of .pkg.tar.zst
    # files that pacstrap will download, including all pulled-in dependencies.
    local total_dl
    total_dl=$(pacman -Sp "${pkgs[@]}" 2>/dev/null | wc -l)
    [[ $total_dl -lt 1 ]] && total_dl=1

    (
        stdbuf -oL pacstrap -K "$mnt" "${pkgs[@]}" --disable-download-timeout \
            2>&1 \
        | stdbuf -oL tee "$cmd_log" \
        | stdbuf -oL awk -v total="$total_dl" '
            /^\([0-9]+\/[0-9]+\)[[:space:]]+Downloading[[:space:]]/ {
                done++
                match($0, /Downloading[[:space:]]+([^[:space:]]+)/, a)
                pkg = a[1]
                sub(/-[0-9].*/, "", pkg)
                pct = (total > 0) ? int(done * 100 / total) : 0
                if (pct > 100) pct = 100
                printf "XXX\n%d\nTéléchargement  %s  (%d/%d)\nXXX\n", pct, pkg, done, total
                fflush()
            }
            END { print "100" }
        ' \
        | dialog --title "$title" \
                 --gauge "Calcul des paquets..." 8 "$DW" 0 >/dev/tty
        echo "${PIPESTATUS[0]}" > "$rc_file"
    )
    local rc; rc=$(cat "$rc_file"); rm -f "$rc_file"

    if [[ "$rc" -ne 0 ]]; then
        local tail_output; tail_output=$(tail -20 "$cmd_log")
        rm -f "$cmd_log"
        error "pacstrap a échoué (code $rc) :\n\n$title\n\nDernières lignes :\n$tail_output"
    fi
    cat "$cmd_log" >> "$_LOG"
    rm -f "$cmd_log"
}

# ══════════════════════════════════════════════════════════
#  ÉTAPE 1 — DÉTECTION AUTOMATIQUE DU MATÉRIEL
# ══════════════════════════════════════════════════════════
banner "DÉTECTION DU MATÉRIEL"

_VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")

_CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null | awk '{print $3}')
case "$_CPU_VENDOR" in
    GenuineIntel) _CPU="intel" ;;
    AuthenticAMD) _CPU="amd" ;;
    *)            _CPU="unknown" ;;
esac

_CHASSIS=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
case "$_CHASSIS" in
    8|9|10|11|14|30|31|32)    _MACHINE="laptop" ;;
    3|4|5|6|7|15|16|17|23|24) _MACHINE="desktop" ;;
    *)                         _MACHINE="unknown" ;;
esac

_GPU_LIST=$(lspci 2>/dev/null | grep -E "VGA|3D|Display" || echo "")
_HAS_NVIDIA=false; _HAS_AMD_GPU=false; _HAS_INTEL_GPU=false
echo "$_GPU_LIST" | grep -qi "nvidia"                       && _HAS_NVIDIA=true
echo "$_GPU_LIST" | grep -qi "advanced micro\|amd\|radeon"  && _HAS_AMD_GPU=true
echo "$_GPU_LIST" | grep -qi "intel"                        && _HAS_INTEL_GPU=true

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

_DETECT_MSG="Configuration détectée automatiquement :\n\n"
_DETECT_MSG+="  Virtualisation : $_VIRT\n"
_DETECT_MSG+="  CPU            : $_CPU_VENDOR ($_CPU)\n"
_DETECT_MSG+="  Machine        : $_MACHINE (chassis $_CHASSIS)\n"
_DETECT_MSG+="  GPUs           :\n"
while IFS= read -r _line; do _DETECT_MSG+="    $_line\n"; done <<< "$_GPU_LIST"
_DETECT_MSG+="\n→ Config retenue : ${_CONFIG_LABELS[$_CONFIG_AUTO]:-$_CONFIG_AUTO}\n\nConfirmer cette configuration ?"

if d_yesno "Détection du matériel" "$_DETECT_MSG"; then
    CONFIG="$_CONFIG_AUTO"
else
    CONFIG=$(d_menu "Sélection manuelle" "Choisissez votre configuration :" \
        "vm"                 "VMware Workstation" \
        "laptop-amd-nvidia"  "Laptop AMD + NVIDIA (Optimus)" \
        "laptop-intel-nvidia" "Laptop Intel + NVIDIA (Optimus)" \
        "laptop-amd"         "Laptop AMD (iGPU seul)" \
        "laptop-intel"       "Laptop Intel (iGPU seul)" \
        "desktop-amd-nvidia" "Desktop AMD + NVIDIA" \
        "desktop-intel-nvidia" "Desktop Intel + NVIDIA" \
        "desktop-amd-amd"    "Desktop AMD + AMD GPU" \
        "desktop-intel-amd"  "Desktop Intel + AMD GPU")
fi

clear
echo -e "\n${GREEN}Config retenue : ${BOLD}${_CONFIG_LABELS[$CONFIG]}${NC}"

_IS_VM=false;        [[ "$CONFIG" == "vm" ]]       && _IS_VM=true
_IS_LAPTOP=false;    [[ "$CONFIG" == laptop* ]]     && _IS_LAPTOP=true
_OPTIMUS=false;      [[ "$CONFIG" == *nvidia* && "$_IS_LAPTOP" == true ]] && _OPTIMUS=true
_NEED_NVIDIA=false;  [[ "$CONFIG" == *nvidia* ]]    && _NEED_NVIDIA=true
_NEED_AMD_GPU=false; [[ "$CONFIG" == *amd-amd* || "$CONFIG" == *intel-amd* || "$CONFIG" == laptop-amd* ]] && _NEED_AMD_GPU=true
_CPU_UCODE=""
if ! $_IS_VM; then
    [[ "$_CPU" == "intel" ]] && _CPU_UCODE="intel-ucode" || _CPU_UCODE="amd-ucode"
fi

# ══════════════════════════════════════════════════════════
#  ÉTAPE 2 — CONFIGURATION
# ══════════════════════════════════════════════════════════
banner "CONFIGURATION"

_DISK_CHECKLIST_ARGS=()
_FIRST_DISK=""
while IFS= read -r _dline; do
    _dname=$(echo "$_dline" | awk '{print $1}')
    _dsize=$(echo "$_dline" | awk '{print $2}')
    _dtran=$(echo "$_dline" | awk '{print $3}')
    _dmodel=$(echo "$_dline" | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//')

    if [[ "$_dname" == nvme* ]]; then
        _dtype="NVMe"
    elif [[ "${_dtran,,}" == "sata" ]]; then
        _dtype="SATA"
    elif [[ "${_dtran,,}" == "ide" ]]; then
        _dtype="IDE"
    elif [[ "${_dtran,,}" == "usb" ]]; then
        _dtype="USB"
    else
        _dtype="SCSI"
    fi

    _tag="/dev/${_dname}"
    _desc="${_dsize} — ${_dtype}"
    [[ -n "$_dmodel" ]] && _desc="${_desc}  [${_dmodel}]"

    [[ -z "$_FIRST_DISK" ]] && _FIRST_DISK="$_tag"
    _status="off"
    [[ "$_tag" == "$_FIRST_DISK" ]] && _status="on"

    _DISK_CHECKLIST_ARGS+=( "$_tag" "$_desc" "$_status" )
done < <(lsblk -d -n -o NAME,SIZE,TRAN,MODEL 2>/dev/null \
    | grep -Ev '^(loop|sr)[0-9]' \
    | awk '$0!=""')

_DISK_RAW=$(d_checklist "Disque cible" \
    "Sélectionnez le disque cible (⚠️  il sera ENTIÈREMENT EFFACÉ) :" \
    "${_DISK_CHECKLIST_ARGS[@]}")

_DISK_COUNT=$(echo "$_DISK_RAW" | wc -w)
if [[ "$_DISK_COUNT" -gt 1 ]]; then
    d_msgbox "Attention" "Plusieurs disques sélectionnés.\nSeul le premier sera utilisé : $(echo $_DISK_RAW | awk '{print $1}')"
fi

DISK=$(echo "$_DISK_RAW" | awk '{print $1}')
[[ -z "$DISK" ]] && error "Aucun disque sélectionné."

if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    EFI_PART="${DISK}p1"; ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1";  ROOT_PART="${DISK}2"
fi

_DEFAULT_HOST="mon-pc"
$_IS_VM      && _DEFAULT_HOST="arch-vm"
$_IS_LAPTOP  && _DEFAULT_HOST="mon-laptop"
[[ "$CONFIG" == desktop* ]] && _DEFAULT_HOST="mon-desktop"

HOSTNAME=$(d_input "Nom de la machine" "Hostname :" "$_DEFAULT_HOST")
USERNAME=$(d_input "Utilisateur" "Nom d'utilisateur :" "Admin")
TIMEZONE=$(d_input "Timezone" "Timezone (ex: Europe/Paris, America/New_York) :" "Europe/Paris")
LOCALE=$(d_input "Locale" "Locale (ex: fr_FR.UTF-8, en_US.UTF-8) :" "fr_FR.UTF-8")
KEYMAP=$(d_input "Clavier console" "Layout clavier (ex: fr, us, de) :" "fr")

_K_SEL=$(d_checklist "Kernels Linux" \
    "Sélectionnez les kernels à installer (Espace = cocher) :" \
    "linux"          "Kernel standard (recommandé)"       "on" \
    "linux-lts"      "Long Term Support (recommandé)"     "on" \
    "linux-zen"      "Optimisé performance"               "off" \
    "linux-hardened" "Kernel sécurisé"                    "off")
KERNELS="$_K_SEL"
[[ -z "${KERNELS// /}" ]] && KERNELS="linux linux-lts"

_DE_SEL=$(d_checklist "Environnements de bureau" \
    "Sélectionnez les DEs à installer :" \
    "kde"      "KDE Plasma — Wayland (recommandé)"   "on" \
    "xfce"     "XFCE4 — X11, léger (recommandé)"     "on" \
    "cinnamon" "Cinnamon — X11, stable"               "off" \
    "gnome"    "GNOME — Wayland"                      "off" \
    "mate"     "MATE — X11, très léger"               "off")

INSTALL_KDE=false;      [[ "$_DE_SEL" == *"kde"*      ]] && INSTALL_KDE=true
INSTALL_XFCE=false;     [[ "$_DE_SEL" == *"xfce"*     ]] && INSTALL_XFCE=true
INSTALL_CINNAMON=false; [[ "$_DE_SEL" == *"cinnamon"* ]] && INSTALL_CINNAMON=true
INSTALL_GNOME=false;    [[ "$_DE_SEL" == *"gnome"*    ]] && INSTALL_GNOME=true
INSTALL_MATE=false;     [[ "$_DE_SEL" == *"mate"*     ]] && INSTALL_MATE=true

AUR_HELPER=$(d_menu "AUR Helper" \
    "Choisissez un AUR helper (requis pour certains paquets) :" \
    "yay"    "Go — le plus populaire (recommandé)" \
    "paru"   "Rust — fork de yay, rapide" \
    "trizen" "Perl — léger" \
    "none"   "Aucun — les paquets AUR ne seront pas installés")

if [[ "$AUR_HELPER" == "none" ]]; then
    d_msgbox "AUR Helper désactivé" \
        "⚠️  Sans AUR helper, les paquets suivants NE seront PAS installés :\n\nBrave, Heroic, Bottles, Discord, Timeshift, VSCode"
fi

_AUR_LABEL_SUFFIX=""
[[ "$AUR_HELPER" == "none" ]] && _AUR_LABEL_SUFFIX=" [AUR — IGNORÉ]" || _AUR_LABEL_SUFFIX=" (AUR)"

_PKG_SEL=$(d_checklist "Sélection des paquets" \
    "Cochez les logiciels à installer (Espace = cocher/décocher) :" \
    \
    "firefox"      "Firefox                        — Navigateur"                "on" \
    "chromium"     "Chromium                       — Navigateur"                "off" \
    "brave"        "Brave${_AUR_LABEL_SUFFIX}      — Navigateur"                "off" \
    \
    "steam"        "Steam                          — Gaming"                    "on" \
    "lutris"       "Lutris                         — Gaming"                    "on" \
    "heroic"       "Heroic${_AUR_LABEL_SUFFIX}     — Epic/GOG"                 "off" \
    "gamemode"     "GameMode                       — Optimiseur de jeux"        "on" \
    "mangohud"     "MangoHud                       — Overlay GPU/CPU"           "on" \
    "bottles"      "Bottles${_AUR_LABEL_SUFFIX}    — Wine manager"              "off" \
    "discord"      "Discord${_AUR_LABEL_SUFFIX}    — Chat gaming"               "off" \
    \
    "obs"          "OBS Studio                     — Streaming/Enregistrement"  "on" \
    "kdenlive"     "Kdenlive                       — Montage vidéo"             "off" \
    "blender"      "Blender                        — 3D"                        "off" \
    "gimp"         "GIMP                           — Retouche photo"            "off" \
    "inkscape"     "Inkscape                       — Dessin vectoriel"          "off" \
    "audacity"     "Audacity                       — Audio"                     "off" \
    \
    "libreoffice"  "LibreOffice                    — Suite bureautique"         "off" \
    "thunderbird"  "Thunderbird                    — Messagerie"                "off" \
    "keepassxc"    "KeePassXC                      — Gestionnaire de mots de passe" "off" \
    "flameshot"    "Flameshot                      — Capture d'écran"           "off" \
    "timeshift"    "Timeshift${_AUR_LABEL_SUFFIX}  — Sauvegarde système"        "off" \
    "gnome-disk"   "Gnome Disk Utility             — Gestion des disques"       "on" \
    \
    "vscode"       "VSCode${_AUR_LABEL_SUFFIX}     — Éditeur de code"          "off" \
    "neovim"       "Neovim                         — Éditeur terminal"          "off" \
    "docker"       "Docker + Compose               — Conteneurs"               "off" \
    \
    "vlc"          "VLC                            — Lecteur multimédia"        "on" \
    "qbittorrent"  "qBittorrent                    — Torrent"                   "off" \
    "filezilla"    "FileZilla                      — FTP/SFTP"                  "off")

if [[ "$AUR_HELPER" == "none" ]]; then
    for _aur_pkg in brave heroic bottles discord timeshift vscode; do
        _PKG_SEL="${_PKG_SEL//$_aur_pkg/}"
    done
fi

_has_pkg() { [[ " $_PKG_SEL " == *" $1 "* ]]; }

PKG_FIREFOX=false;     _has_pkg firefox     && PKG_FIREFOX=true
PKG_CHROMIUM=false;    _has_pkg chromium     && PKG_CHROMIUM=true
PKG_BRAVE=false;       _has_pkg brave        && PKG_BRAVE=true
PKG_STEAM=false;       _has_pkg steam        && PKG_STEAM=true
PKG_LUTRIS=false;      _has_pkg lutris       && PKG_LUTRIS=true
PKG_HEROIC=false;      _has_pkg heroic       && PKG_HEROIC=true
PKG_GAMEMODE=false;    _has_pkg gamemode     && PKG_GAMEMODE=true
PKG_MANGOHUD=false;    _has_pkg mangohud     && PKG_MANGOHUD=true
PKG_BOTTLES=false;     _has_pkg bottles      && PKG_BOTTLES=true
PKG_DISCORD=false;     _has_pkg discord      && PKG_DISCORD=true
PKG_OBS=false;         _has_pkg obs          && PKG_OBS=true
PKG_KDENLIVE=false;    _has_pkg kdenlive     && PKG_KDENLIVE=true
PKG_BLENDER=false;     _has_pkg blender      && PKG_BLENDER=true
PKG_GIMP=false;        _has_pkg gimp         && PKG_GIMP=true
PKG_INKSCAPE=false;    _has_pkg inkscape     && PKG_INKSCAPE=true
PKG_AUDACITY=false;    _has_pkg audacity     && PKG_AUDACITY=true
PKG_LIBREOFFICE=false; _has_pkg libreoffice  && PKG_LIBREOFFICE=true
PKG_THUNDERBIRD=false; _has_pkg thunderbird  && PKG_THUNDERBIRD=true
PKG_KEEPASSXC=false;   _has_pkg keepassxc    && PKG_KEEPASSXC=true
PKG_FLAMESHOT=false;   _has_pkg flameshot    && PKG_FLAMESHOT=true
PKG_TIMESHIFT=false;   _has_pkg timeshift    && PKG_TIMESHIFT=true
PKG_GNOME_DISK=false;  _has_pkg gnome-disk   && PKG_GNOME_DISK=true
PKG_VSCODE=false;      _has_pkg vscode       && PKG_VSCODE=true
PKG_NEOVIM=false;      _has_pkg neovim       && PKG_NEOVIM=true
PKG_DOCKER=false;      _has_pkg docker       && PKG_DOCKER=true
PKG_VLC=false;         _has_pkg vlc          && PKG_VLC=true
PKG_QBITTORRENT=false; _has_pkg qbittorrent  && PKG_QBITTORRENT=true
PKG_FILEZILLA=false;   _has_pkg filezilla    && PKG_FILEZILLA=true

_SUMMARY="Configuration retenue :\n\n"
_SUMMARY+="  Config   : ${_CONFIG_LABELS[$CONFIG]}\n"
_SUMMARY+="  Disque   : $DISK  (EFI=$EFI_PART  ROOT=$ROOT_PART)\n"
_SUMMARY+="  Hostname : $HOSTNAME\n"
_SUMMARY+="  User     : $USERNAME\n"
_SUMMARY+="  Timezone : $TIMEZONE\n"
_SUMMARY+="  Locale   : $LOCALE\n"
_SUMMARY+="  Clavier  : $KEYMAP\n"
_SUMMARY+="  Kernels  : $KERNELS\n"
_SUMMARY+="  AUR      : $AUR_HELPER\n"
_SUMMARY+="  Paquets  : $_PKG_SEL"
d_msgbox "Récapitulatif" "$_SUMMARY"

# ── Vérification du disque ────────────────────────────────
[[ -b "$DISK" ]] || error "Disque $DISK introuvable."

# ── Mots de passe ─────────────────────────────────────────
while true; do
    ROOT_PASS=$(d_password  "Mot de passe root" "Mot de passe root :")
    ROOT_PASS2=$(d_password "Mot de passe root" "Confirmer le mot de passe root :")
    if [[ "$ROOT_PASS" != "$ROOT_PASS2" ]]; then
        d_msgbox "Erreur" "Les mots de passe root ne correspondent pas. Réessayez."
        continue
    fi
    if [[ ${#ROOT_PASS} -lt 6 ]]; then
        d_yesno "Mot de passe faible" \
            "⚠️  Le mot de passe root est très court (< 6 caractères).\nContinuer quand même ?" \
            || continue
    fi
    break
done

while true; do
    USER_PASS=$(d_password  "Mot de passe $USERNAME" "Mot de passe pour $USERNAME :")
    USER_PASS2=$(d_password "Mot de passe $USERNAME" "Confirmer le mot de passe :")
    if [[ "$USER_PASS" != "$USER_PASS2" ]]; then
        d_msgbox "Erreur" "Les mots de passe ne correspondent pas. Réessayez."
        continue
    fi
    if [[ ${#USER_PASS} -lt 6 ]]; then
        d_yesno "Mot de passe faible" \
            "⚠️  Le mot de passe de $USERNAME est très court (< 6 caractères).\nContinuer quand même ?" \
            || continue
    fi
    break
done

# ── Confirmation finale ───────────────────────────────────
d_yesno "⚠️  CONFIRMATION FINALE" \
    "ATTENTION : $DISK va être ENTIÈREMENT EFFACÉ et reformaté.\n\nToutes les données seront perdues de manière irréversible.\n\nLancer l'installation ?" \
    || error "Installation annulée par l'utilisateur."

clear

# ══════════════════════════════════════════════════════════
#  INSTALLATION — ÉTAPES AVEC BARRES DE PROGRESSION
# ══════════════════════════════════════════════════════════

# ── Démontage préalable ───────────────────────────────────
d_run_gauge 0 "Préparation" "Démontage des partitions existantes..." bash -c "
    if mountpoint -q /mnt; then
        umount -R /mnt 2>/dev/null || umount -R -l /mnt 2>/dev/null || true
    fi
    for PART in \$(lsblk -ln -o NAME,MOUNTPOINT '$DISK' 2>/dev/null | awk '\$2!=\"\" {print \"/dev/\"\$1}'); do
        umount -l \"\$PART\" 2>/dev/null || true
    done
"

# ── Partitionnement ───────────────────────────────────────
d_run_gauge 10 "Partitionnement" "Création des partitions sur $DISK..." bash -c "
    sgdisk -Z '$DISK' 2>/dev/null || true
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:'EFI'  '$DISK'
    sgdisk -n 2:0:0     -t 2:8300 -c 2:'ROOT' '$DISK'
"

# ── Formatage ─────────────────────────────────────────────
{
    echo 20
    echo "XXXFormatage EFI en FAT32..."
    mkfs.fat -F32 "$EFI_PART" >>"$_LOG" 2>&1
    echo 40
    echo "XXXFormatage ROOT en ext4..."
    mkfs.ext4 -F "$ROOT_PART" >>"$_LOG" 2>&1
    echo 100
    echo "XXXFormatage terminé."
} | dialog --title "Formatage" --gauge "Formatage des partitions..." 8 "$DW" 0 >/dev/tty

# ── Montage ───────────────────────────────────────────────
d_run_gauge 50 "Montage" "Montage des partitions..." bash -c "
    mount '$ROOT_PART' /mnt
    mkdir -p /mnt/boot/efi
    mount '$EFI_PART' /mnt/boot/efi
"

# ── Miroirs ───────────────────────────────────────────────
d_run_gauge 60 "Miroirs" "Sélection des miroirs (France, HTTPS, triés par vitesse)..." \
    reflector --country France --age 12 --protocol https --sort rate \
              --connection-timeout 5 --latest 20 \
              --save /etc/pacman.d/mirrorlist

# ── pacstrap ─────────────────────────────────────────────
_UCODE_PKG=""
if ! $_IS_VM; then
    [[ "$_CPU" == "intel" ]] && _UCODE_PKG="intel-ucode" || _UCODE_PKG="amd-ucode"
fi

pacstrap_gauge "📦 Base système — pacstrap" /mnt \
    base base-devel ${KERNELS} linux-firmware \
    ${_UCODE_PKG} \
    networkmanager \
    grub efibootmgr \
    nano vim git curl wget \
    gptfdisk

# ── fstab ─────────────────────────────────────────────────
d_run_gauge 5 "Configuration" "Génération du fstab..." \
    bash -c "genfstab -U /mnt >> /mnt/etc/fstab"

# ══════════════════════════════════════════════════════════
#  CONFIGURATION (CHROOT)
# ══════════════════════════════════════════════════════════

# The chroot script is written to a temp file so that d_progress_box
# can stream its output live into a progressbox dialog.
_CHROOT_SCRIPT=$(mktemp /mnt/root/chroot-XXXXXX.sh)
chmod +x "$_CHROOT_SCRIPT"

cat > "$_CHROOT_SCRIPT" << CHROOT_SCRIPT
#!/bin/bash
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "\n\${BLUE}[INFO]\${NC} \$1"; }
success() { echo -e "\${GREEN}[OK]\${NC} \$1"; }
warn()    { echo -e "\${YELLOW}[WARN]\${NC} \$1"; }
banner()  { echo -e "\n\${BOLD}══ \$1 ══\${NC}"; }

# In the chroot, dialog is not installed — all output is streamed to the
# host-side d_progress_box progressbox. pacman_gauge here is just a thin
# wrapper around plain pacman -S that prints a banner and exits on failure.
pacman_gauge() {
    local title="\$1"; shift
    echo -e "\n\${BLUE}[INSTALL]\${NC} \$title"
    pacman -S --noconfirm --disable-download-timeout "\$@"
    local rc=\$?
    if [[ "\$rc" -ne 0 ]]; then
        echo -e "\${RED}[ERREUR]\${NC} pacman a échoué (code \$rc) — \$title"
        exit 1
    fi
}

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
ln -sf /usr/share/zoneinfo/\${TIMEZONE} /etc/localtime
hwclock --systohc
success "Timezone : \${TIMEZONE}"

# ── Locale ────────────────────────────────────────────────
banner "LOCALE"
sed -i "s/^#\${LOCALE}/\${LOCALE}/" /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=\${LOCALE}" > /etc/locale.conf
echo "KEYMAP=\${KEYMAP}" > /etc/vconsole.conf
success "Locale : \${LOCALE} — Clavier : \${KEYMAP}"

# ── Hostname ──────────────────────────────────────────────
banner "HOSTNAME"
echo "\${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HOSTNAME}.localdomain \${HOSTNAME}
EOF
success "Hostname : \${HOSTNAME}"

# ── Utilisateurs ──────────────────────────────────────────
banner "UTILISATEURS"
echo "root:\${ROOT_PASS}" | chpasswd
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "\${USERNAME}"
echo "\${USERNAME}:\${USER_PASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
success "Utilisateurs créés"

# ── Clavier X11 ───────────────────────────────────────────
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "\${KEYMAP}"
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

if [[ "\${_IS_VM}" == "true" ]]; then
    info "Installation drivers VMware..."
    pacman_gauge "Drivers VMware" \
        mesa xf86-input-vmmouse xf86-video-fbdev vulkan-icd-loader \
        open-vm-tools
    success "Drivers VMware installés"

elif [[ "\${_NEED_NVIDIA}" == "true" && "\${_NEED_AMD_GPU}" == "true" ]]; then
    info "Installation drivers Optimus (AMD iGPU + NVIDIA dGPU)..."
    pacman_gauge "Drivers Optimus — AMD" \
        mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu
    pacman_gauge "Drivers Optimus — NVIDIA" \
        nvidia nvidia-utils nvidia-settings \
        lib32-nvidia-utils lib32-mesa
    pacman_gauge "Drivers Optimus — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader
    echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
    sed -i 's/^MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    pacman_gauge "Drivers Optimus — switcheroo" switcheroo-control
    success "Drivers Optimus installés"

elif [[ "\${_NEED_NVIDIA}" == "true" ]]; then
    info "Installation drivers NVIDIA..."
    pacman_gauge "Drivers NVIDIA" \
        nvidia nvidia-utils nvidia-settings \
        lib32-nvidia-utils lib32-mesa
    pacman_gauge "Drivers NVIDIA — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader
    echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
    sed -i 's/^MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    success "Drivers NVIDIA installés"

elif [[ "\${_NEED_AMD_GPU}" == "true" ]]; then
    info "Installation drivers AMD GPU..."
    pacman_gauge "Drivers AMD GPU" \
        mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu \
        lib32-mesa lib32-vulkan-radeon
    pacman_gauge "Drivers AMD GPU — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader
    success "Drivers AMD GPU installés"

else
    info "Installation drivers Intel iGPU..."
    pacman_gauge "Drivers Intel iGPU" \
        mesa vulkan-intel intel-media-driver \
        lib32-mesa lib32-vulkan-intel
    pacman_gauge "Drivers Intel — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader
    success "Drivers Intel installés"
fi

# ── Pipewire ──────────────────────────────────────────────
banner "PIPEWIRE"
pacman_gauge "Pipewire — audio" \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack \
    wireplumber
success "Pipewire installé"

# ── Environnements de bureau ──────────────────────────────
if [[ "\${INSTALL_KDE}" == "true" ]]; then
    banner "KDE PLASMA"
    pacman_gauge "KDE Plasma" \
        plasma-meta sddm \
        dolphin konsole kate ark gwenview okular spectacle yakuake
    success "KDE Plasma installé"
fi

if [[ "\${INSTALL_XFCE}" == "true" ]]; then
    banner "XFCE4"
    pacman_gauge "XFCE4" xfce4 xfce4-goodies
    success "XFCE4 installé"
fi

if [[ "\${INSTALL_CINNAMON}" == "true" ]]; then
    banner "CINNAMON"
    pacman_gauge "Cinnamon" cinnamon
    success "Cinnamon installé"
fi

if [[ "\${INSTALL_GNOME}" == "true" ]]; then
    banner "GNOME"
    pacman_gauge "GNOME" gnome gnome-extra
    success "GNOME installé"
fi

if [[ "\${INSTALL_MATE}" == "true" ]]; then
    banner "MATE"
    pacman_gauge "MATE" mate mate-extra
    success "MATE installé"
fi

if [[ "\${INSTALL_KDE}" == "false" ]]; then
    pacman_gauge "LightDM" lightdm lightdm-gtk-greeter
    systemctl enable lightdm 2>/dev/null || true
fi

# ── AUR Helper ────────────────────────────────────────────
if [[ "\${AUR_HELPER}" != "none" ]]; then
    banner "AUR HELPER — \${AUR_HELPER}"
    pacman_gauge "AUR Helper — dépendances" go git base-devel
    cd /tmp
    git clone "https://aur.archlinux.org/\${AUR_HELPER}.git"
    chmod 777 "/tmp/\${AUR_HELPER}"
    cd "/tmp/\${AUR_HELPER}"
    sudo -u "${USERNAME}" makepkg -si --noconfirm
    cd /
    rm -rf "/tmp/\${AUR_HELPER}"
    success "\${AUR_HELPER} installé"
fi

# ── Logiciels supplémentaires ─────────────────────────────
banner "LOGICIELS SUPPLÉMENTAIRES"
_PACMAN_PKGS="htop fastfetch"
_AUR_PKGS=""

[[ "\${PKG_FIREFOX}"     == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS firefox"
[[ "\${PKG_CHROMIUM}"    == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS chromium"
[[ "\${PKG_BRAVE}"       == "true" ]] && _AUR_PKGS="\$_AUR_PKGS brave-bin"
[[ "\${PKG_STEAM}"       == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS steam"
[[ "\${PKG_LUTRIS}"      == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS lutris"
[[ "\${PKG_HEROIC}"      == "true" ]] && _AUR_PKGS="\$_AUR_PKGS heroic-games-launcher-bin"
[[ "\${PKG_GAMEMODE}"    == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS gamemode lib32-gamemode"
[[ "\${PKG_MANGOHUD}"    == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS mangohud lib32-mangohud"
[[ "\${PKG_BOTTLES}"     == "true" ]] && _AUR_PKGS="\$_AUR_PKGS bottles"
[[ "\${PKG_DISCORD}"     == "true" ]] && _AUR_PKGS="\$_AUR_PKGS discord"
[[ "\${PKG_OBS}"         == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS obs-studio"
[[ "\${PKG_KDENLIVE}"    == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS kdenlive"
[[ "\${PKG_BLENDER}"     == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS blender"
[[ "\${PKG_GIMP}"        == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS gimp"
[[ "\${PKG_INKSCAPE}"    == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS inkscape"
[[ "\${PKG_AUDACITY}"    == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS audacity"
[[ "\${PKG_LIBREOFFICE}" == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS libreoffice-fresh"
[[ "\${PKG_THUNDERBIRD}" == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS thunderbird"
[[ "\${PKG_KEEPASSXC}"   == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS keepassxc"
[[ "\${PKG_FLAMESHOT}"   == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS flameshot"
[[ "\${PKG_TIMESHIFT}"   == "true" ]] && _AUR_PKGS="\$_AUR_PKGS timeshift"
[[ "\${PKG_GNOME_DISK}"  == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS gnome-disk-utility"
[[ "\${PKG_NEOVIM}"      == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS neovim"
[[ "\${PKG_DOCKER}"      == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS docker docker-compose"
[[ "\${PKG_VSCODE}"      == "true" ]] && _AUR_PKGS="\$_AUR_PKGS visual-studio-code-bin"
[[ "\${PKG_VLC}"         == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS vlc"
[[ "\${PKG_QBITTORRENT}" == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS qbittorrent"
[[ "\${PKG_FILEZILLA}"   == "true" ]] && _PACMAN_PKGS="\$_PACMAN_PKGS filezilla"

pacman_gauge "Logiciels supplémentaires" \${_PACMAN_PKGS}
success "Logiciels pacman installés"

[[ "\${PKG_DOCKER}" == "true" ]] && systemctl enable docker 2>/dev/null || true

if [[ -n "\${_AUR_PKGS## }" && "\${AUR_HELPER}" != "none" ]]; then
    info "Installation des paquets AUR via \${AUR_HELPER}..."
    sudo -u "${USERNAME}" \${AUR_HELPER} -S --noconfirm --mflags "--nocheck" \${_AUR_PKGS}
    success "Paquets AUR installés"
fi

# ── SDDM ──────────────────────────────────────────────────
banner "SDDM"
mkdir -p /etc/systemd/system/sddm.service.d
cat > /etc/systemd/system/sddm.service.d/locale.conf << EOF
[Service]
Environment=LANG=en_US.UTF-8
EOF
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf.user << EOF
[Theme]
Current=breeze
CursorTheme=breeze_cursors
Background=/usr/share/wallpapers/Next/contents/images_dark/5120x2880.png
EOF
success "SDDM configuré"

# ── Clavier KDE ───────────────────────────────────────────
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

if [[ "\${_IS_VM}" == "true" ]]; then
    systemctl enable vmtoolsd
    systemctl enable vmware-vmblock-fuse
    success "Services activés : NetworkManager, SDDM, vmtoolsd, vmware-vmblock-fuse"
elif [[ "\${_OPTIMUS}" == "true" ]]; then
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

# ── Nettoyage — suppression du script d'installation ──────
rm -f "$0"
CHROOT_SCRIPT

# ── Exécution chroot avec progressbox ────────────────────
d_progress_box "⚙️  Configuration du système (chroot)" \
    arch-chroot /mnt /bin/bash "${_CHROOT_SCRIPT#/mnt}"

# ── Démontage final ───────────────────────────────────────
d_run_gauge 95 "Finalisation" "Démontage des partitions..." bash -c "
    sync
    umount -R -l /mnt
"

# ══════════════════════════════════════════════════════════
#  FIN
# ══════════════════════════════════════════════════════════
clear
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

# Copie du log dans le système installé
if mountpoint -q /mnt 2>/dev/null; then
    cp "$LOG_FILE" /mnt/root/ais.log 2>/dev/null || true
fi
echo "📄 Log disponible dans /root/ais.log"

echo -e "${NC}"