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
# Tout envoyer dans le log — dialog écrit directement sur /dev/tty
# donc il n'est pas affecté par cette redirection
exec > >(tee -a "$LOG_FILE" >/dev/null) 2>&1
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

# _cache_gauge <title> <cache_dir> <db_dir> <cmd...>
# Tracks both download (cache) and install (db_dir) phases.
# Phase 0: spinner while pacman resolves deps
# Phase 1 (0→49%): watches cache_dir for new .pkg.tar.zst + .part files
# Phase 2 (50→99%): watches db_dir for new installed package entries
_cache_gauge() {
    local title="$1" cache_dir="$2" db_dir="$3"; shift 3
    local cmd_log; cmd_log=$(mktemp)
    local rc_file; rc_file=$(mktemp)

    # Pré-calculer le total attendu via dry-run (print only)
    # DB déjà synchronisée par la phase de résolution initiale
    local total_expected=0
    local first_cmd="$1"
    if [[ "$first_cmd" == "pacman" ]]; then
        total_expected=$(pacman -Sp --print-format '%n' "${@:2}" 2>/dev/null \
                         | grep -v "^error" | wc -l) || true
    elif [[ "$first_cmd" == "arch-chroot" ]]; then
        local chroot_pkgs=("${@:3}")
        [[ "${_DB_SYNCED:-false}" != "true" ]] && arch-chroot /mnt pacman -Sy &>/dev/null || true
        total_expected=$(arch-chroot /mnt pacman -Sp --print-format '%n' \
                         "${chroot_pkgs[@]:1}" 2>/dev/null | grep -v "^error" | wc -l) || true
    elif [[ "$first_cmd" == "pacstrap" ]]; then
        total_expected=$(pacman -Sp --print-format '%n' "${@:3}" 2>/dev/null \
                         | grep -v "^error" | wc -l) || true
    fi
    [[ -z "$total_expected" || "$total_expected" -lt 1 ]] && total_expected=0

    # Baselines
    local baseline_cache baseline_db
    baseline_cache=$(find "$cache_dir" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' ! -name '*.part' \
                     2>/dev/null | wc -l)
    baseline_db=$(find "$db_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)

    ("$@" >"$cmd_log" 2>&1; echo $? >"$rc_file") &
    local bg_pid=$!

    (
        local last_label="..." phase="Téléchargement" prev_cached=0 total_seen=0
        local spin_idx=0
        local -a spin_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

        while kill -0 "$bg_pid" 2>/dev/null; do
            local cached in_progress installed
            # Paquets téléchargés (complets)
            cached=$(find "$cache_dir" -maxdepth 1 -name '*.pkg.tar.*' \
                     ! -name '*.sig' ! -name '*.part' 2>/dev/null | wc -l)
            # Téléchargements en cours (.part)
            in_progress=$(find "$cache_dir" -maxdepth 1 -name '*.part' 2>/dev/null | wc -l)
            # Paquets installés
            installed=$(find "$db_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)

            local done_dl=$(( cached - baseline_cache ))
            local done_inst=$(( installed - baseline_db ))
            [[ $done_dl -lt 0 ]] && done_dl=0
            [[ $done_inst -lt 0 ]] && done_inst=0

            # Mise à jour du total vu (max entre ce qu'on voit et ce qu'on a vu)
            local current_seen=$(( done_dl + in_progress ))
            [[ $current_seen -gt $total_seen ]] && total_seen=$current_seen

            spin_idx=$(( (spin_idx + 1) % 10 ))
            local spin="${spin_chars[$spin_idx]}"

            if [[ $done_dl -eq 0 && $in_progress -eq 0 && $done_inst -eq 0 ]]; then
                # Phase préparation — pacman résout les dépendances
                printf "XXX\n0\nPréparation  %s  Résolution des dépendances...\nXXX\n" "$spin"

            elif [[ $done_dl -gt 0 && $done_dl -eq $prev_cached && $in_progress -eq 0 && $done_inst -gt 0 ]]; then
                # Phase 2 — Installation après téléchargement
                phase="Installation"
                local total_to_install=$done_dl
                local pct=$(( 50 + done_inst * 50 / ( total_to_install > 0 ? total_to_install : 1 ) ))
                [[ $pct -gt 99 ]] && pct=99

                local newest_inst
                newest_inst=$(find "$db_dir" -maxdepth 1 -mindepth 1 -type d \
                              -printf '%T@ %f\n' 2>/dev/null \
                              | sort -n | tail -1 | awk '{print $2}' \
                              | sed 's/-[0-9].*//')
                [[ -n "$newest_inst" ]] && last_label="$newest_inst"

                printf "XXX\n%d\n%s  %s  (%d/%d)\nXXX\n" \
                    "$pct" "$phase" "$last_label" "$done_inst" "$total_to_install"

            elif [[ $done_dl -eq 0 && $in_progress -eq 0 && $done_inst -gt 0 ]]; then
                # Paquets déjà en cache — installation directe
                phase="Installation (cache)"
                local pct=$(( done_inst * 99 / ( total_seen > 0 ? total_seen : done_inst + 1 ) ))
                [[ $pct -gt 99 ]] && pct=99

                local newest_inst
                newest_inst=$(find "$db_dir" -maxdepth 1 -mindepth 1 -type d \
                              -printf '%T@ %f\n' 2>/dev/null \
                              | sort -n | tail -1 | awk '{print $2}' \
                              | sed 's/-[0-9].*//')
                [[ -n "$newest_inst" ]] && last_label="$newest_inst"

                printf "XXX\n%d\n%s  %s  (%d paquets)\nXXX\n" \
                    "$pct" "$phase" "$last_label" "$done_inst"

            else
                # Phase 1 — Téléchargement
                prev_cached=$done_dl
                phase="Téléchargement"
                local current_total=$(( done_dl + in_progress ))
                [[ $current_total -gt $total_seen ]] && total_seen=$current_total

                local denom
                if [[ $total_expected -gt 0 ]]; then
                    denom=$total_expected
                else
                    denom=$(( total_seen > 1 ? total_seen : current_total + 1 ))
                fi
                local pct=$(( current_total * 49 / ( denom > 0 ? denom : 1 ) ))
                [[ $pct -gt 49 ]] && pct=49

                local newest_part
                newest_part=$(find "$cache_dir" -maxdepth 1 -name '*.part' \
                              -printf '%T@ %f\n' 2>/dev/null \
                              | sort -n | tail -1 | awk '{print $2}' \
                              | sed 's/-[0-9].*//;s/\.part//')
                if [[ -z "$newest_part" ]]; then
                    newest_part=$(find "$cache_dir" -maxdepth 1 -name '*.pkg.tar.*' \
                                  ! -name '*.sig' ! -name '*.part' \
                                  -printf '%T@ %f\n' 2>/dev/null \
                                  | sort -n | tail -1 | awk '{print $2}' \
                                  | sed 's/-[0-9].*//')
                fi
                [[ -n "$newest_part" ]] && last_label="$newest_part"

                if [[ $total_expected -gt 0 ]]; then
                    printf "XXX\n%d\n%s  %s  (%d/%d)\nXXX\n" \
                        "$pct" "$phase" "$last_label" "$current_total" "$total_expected"
                else
                    printf "XXX\n%d\n%s  %s  (%d paquets)\nXXX\n" \
                        "$pct" "$phase" "$last_label" "$current_total"
                fi
            fi
            sleep 0.3
        done
        echo "100"
    ) | dialog --title "$title" \
               --gauge "Démarrage..." 8 "$DW" 0 >/dev/tty

    wait "$bg_pid" 2>/dev/null || true
    local rc=0
    [[ -f "$rc_file" ]] && rc=$(cat "$rc_file")
    rm -f "$rc_file"

    if [[ "$rc" -ne 0 ]]; then
        local tail_output; tail_output=$(tail -20 "$cmd_log")
        cat "$cmd_log" >> "$_LOG" 2>/dev/null || true
        rm -f "$cmd_log"
        error "La commande a échoué (code $rc) :\n\n$title\n\nDernières lignes :\n$tail_output"
    fi
    # Flush dans le log principal ET dans LOG_FILE via stdout
    cat "$cmd_log" >> "$_LOG" 2>/dev/null || true
    cat "$cmd_log"  # envoyer vers stdout→tee→LOG_FILE
    rm -f "$cmd_log"
}

# pacman_gauge <title> <pkg1> [pkg2 ...]
pacman_gauge() {
    local title="$1"; shift
    local pkgs=()
    for p in "$@"; do [[ -n "$p" ]] && pkgs+=("$p"); done
    _cache_gauge "$title" \
        /var/cache/pacman/pkg \
        /var/lib/pacman/local \
        pacman -S --noconfirm --disable-download-timeout "${pkgs[@]}"
}

# pacstrap_gauge <title> <mountpoint> <pkg1> [pkg2 ...]
pacstrap_gauge() {
    local title="$1" mnt="$2"; shift 2
    local pkgs=()
    for p in "$@"; do [[ -n "$p" ]] && pkgs+=("$p"); done
    _cache_gauge "$title" \
        "${mnt}/var/cache/pacman/pkg" \
        "${mnt}/var/lib/pacman/local" \
        pacstrap -K "$mnt" "${pkgs[@]}" --disable-download-timeout
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

# ── Timezone — sélection en 2 niveaux ────────────────────
_TZ_REGIONS=$(timedatectl list-timezones 2>/dev/null | cut -d/ -f1 | sort -u)
_TZ_REGION_ARGS=()
while IFS= read -r _r; do
    _TZ_REGION_ARGS+=("$_r" "$_r")
done <<< "$_TZ_REGIONS"
_TZ_REGION=$(d_menu "Fuseau horaire — Région" "Choisissez votre région :" "${_TZ_REGION_ARGS[@]}")
[[ -z "$_TZ_REGION" ]] && _TZ_REGION="Europe"

_TZ_CITIES=$(timedatectl list-timezones 2>/dev/null | grep "^${_TZ_REGION}/" | cut -d/ -f2 | sort)
_TZ_CITY_ARGS=()
while IFS= read -r _c; do
    _TZ_CITY_ARGS+=("$_c" "$_c")
done <<< "$_TZ_CITIES"
_TZ_CITY=$(d_menu "Fuseau horaire — Ville" "Choisissez votre ville :" "${_TZ_CITY_ARGS[@]}")
[[ -z "$_TZ_CITY" ]] && _TZ_CITY="Paris"
TIMEZONE="${_TZ_REGION}/${_TZ_CITY}"

# ── Locale — liste des plus communes ─────────────────────
LOCALE=$(d_menu "Locale système" "Choisissez votre locale :" \
    "fr_FR.UTF-8"  "Français (France)" \
    "fr_BE.UTF-8"  "Français (Belgique)" \
    "fr_CA.UTF-8"  "Français (Canada)" \
    "fr_CH.UTF-8"  "Français (Suisse)" \
    "en_US.UTF-8"  "English (United States)" \
    "en_GB.UTF-8"  "English (United Kingdom)" \
    "en_CA.UTF-8"  "English (Canada)" \
    "de_DE.UTF-8"  "Deutsch (Deutschland)" \
    "de_AT.UTF-8"  "Deutsch (Österreich)" \
    "de_CH.UTF-8"  "Deutsch (Schweiz)" \
    "es_ES.UTF-8"  "Español (España)" \
    "es_MX.UTF-8"  "Español (México)" \
    "it_IT.UTF-8"  "Italiano (Italia)" \
    "pt_PT.UTF-8"  "Português (Portugal)" \
    "pt_BR.UTF-8"  "Português (Brasil)" \
    "nl_NL.UTF-8"  "Nederlands (Nederland)" \
    "pl_PL.UTF-8"  "Polski (Polska)" \
    "ru_RU.UTF-8"  "Русский (Россия)" \
    "zh_CN.UTF-8"  "中文 (中国)" \
    "ja_JP.UTF-8"  "日本語 (日本)" \
    "ko_KR.UTF-8"  "한국어 (한국)")
[[ -z "$LOCALE" ]] && LOCALE="fr_FR.UTF-8"

# ── Clavier — sélection par langue puis variante ─────────
_KEYMAP_LANG=$(d_menu "Clavier — Langue" "Choisissez votre langue clavier :" \
    "fr"    "Français — AZERTY" \
    "us"    "English — QWERTY (US)" \
    "gb"    "English — QWERTY (UK)" \
    "de"    "Deutsch — QWERTZ" \
    "de-latin1" "Deutsch — QWERTZ (latin1)" \
    "es"    "Español — QWERTY" \
    "it"    "Italiano — QWERTY" \
    "pt"    "Português" \
    "pt-latin1" "Português (latin1)" \
    "be"    "Belgique — AZERTY" \
    "ch"    "Suisse — QWERTZ" \
    "ru"    "Русский — ЙЦУКЕН" \
    "pl"    "Polski — QWERTY" \
    "nl"    "Nederlands — QWERTY" \
    "dk"    "Dansk — QWERTY" \
    "no"    "Norsk — QWERTY" \
    "sv"    "Svenska — QWERTY" \
    "fi"    "Suomi — QWERTY" \
    "hu"    "Magyar — QWERTY" \
    "ro"    "Română — QWERTY" \
    "tr"    "Türkçe — Q" \
    "jp106" "日本語 — 106キー")
[[ -z "$_KEYMAP_LANG" ]] && _KEYMAP_LANG="fr"
KEYMAP="$_KEYMAP_LANG"

_K_SEL=$(d_checklist "Kernels Linux" \
    "Sélectionnez les kernels à installer (Espace = cocher) :" \
    "linux"          "Kernel standard (recommandé)"       "on" \
    "linux-lts"      "Long Term Support (recommandé)"     "on" \
    "linux-zen"      "Optimisé performance"               "off" \
    "linux-hardened" "Kernel sécurisé"                    "off")
KERNELS="$_K_SEL"
[[ -z "${KERNELS// /}" ]] && KERNELS="linux linux-lts"

_DE_SEL=$(d_checklist "Environnements de bureau" \
    "Sélectionnez les DEs à installer (Espace = cocher) :" \
    \
    "---FULL---"   "━━━━━━━━  COMPLETS (Full Desktop)  ━━━━━━━━"    "off" \
    "kde"          "KDE Plasma    — Wayland/X11, moderne"            "on" \
    "gnome"        "GNOME         — Wayland, épuré"                  "off" \
    "cinnamon"     "Cinnamon      — X11, Windows-like (Mint)"        "off" \
    "mate"         "MATE          — X11, classique, léger"            "off" \
    "budgie"       "Budgie        — X11/Wayland, élégant (Solus)"    "off" \
    "lxqt"         "LXQt          — X11, très léger (Lubuntu)"       "off" \
    \
    "---LIGHT---"  "━━━━━━━━━━  LÉGERS (Lightweight)  ━━━━━━━━━━"   "off" \
    "xfce"         "XFCE4         — X11, léger et stable"            "on" \
    "openbox"      "Openbox       — X11, minimaliste (Crunchbang)"   "off" \
    \
    "---TILING---" "━━━━━━━━━  TILING (Gestionnaires)  ━━━━━━━━━"   "off" \
    "i3"           "i3            — X11 tiling (Manjaro i3)"         "off" \
    "sway"         "Sway          — Wayland tiling (i3 Wayland)"     "off" \
    "hyprland"     "Hyprland      — Wayland tiling (CachyOS)"        "off" \
    "bspwm"        "BSPWM         — X11 tiling scriptable"           "off" \
    "awesome"      "AwesomeWM     — X11 tiling + Lua"                "off")

INSTALL_KDE=false;      [[ "$_DE_SEL" == *"kde"*      ]] && INSTALL_KDE=true
INSTALL_GNOME=false;    [[ "$_DE_SEL" == *"gnome"*    ]] && INSTALL_GNOME=true
INSTALL_CINNAMON=false; [[ "$_DE_SEL" == *"cinnamon"* ]] && INSTALL_CINNAMON=true
INSTALL_MATE=false;     [[ "$_DE_SEL" == *"mate"*     ]] && INSTALL_MATE=true
INSTALL_BUDGIE=false;   [[ "$_DE_SEL" == *"budgie"*   ]] && INSTALL_BUDGIE=true
INSTALL_LXQT=false;     [[ "$_DE_SEL" == *"lxqt"*    ]] && INSTALL_LXQT=true
INSTALL_XFCE=false;     [[ "$_DE_SEL" == *"xfce"*     ]] && INSTALL_XFCE=true
INSTALL_OPENBOX=false;  [[ "$_DE_SEL" == *"openbox"*  ]] && INSTALL_OPENBOX=true
INSTALL_I3=false;       [[ "$_DE_SEL" == *"i3"*       ]] && INSTALL_I3=true
INSTALL_SWAY=false;     [[ "$_DE_SEL" == *"sway"*     ]] && INSTALL_SWAY=true
INSTALL_HYPRLAND=false; [[ "$_DE_SEL" == *"hyprland"* ]] && INSTALL_HYPRLAND=true
INSTALL_BSPWM=false;    [[ "$_DE_SEL" == *"bspwm"*    ]] && INSTALL_BSPWM=true
INSTALL_AWESOME=false;  [[ "$_DE_SEL" == *"awesome"*  ]] && INSTALL_AWESOME=true

# ── Display Manager ────────────────────────────────────────
_DM_DEFAULT="sddm"
$INSTALL_GNOME && ! $INSTALL_KDE && _DM_DEFAULT="gdm"
! $INSTALL_KDE && ! $INSTALL_GNOME && _DM_DEFAULT="lightdm"
($INSTALL_I3 || $INSTALL_SWAY || $INSTALL_HYPRLAND || $INSTALL_BSPWM || $INSTALL_AWESOME) \
    && ! $INSTALL_KDE && ! $INSTALL_GNOME && _DM_DEFAULT="ly"

DISPLAY_MANAGER=$(d_menu "Display Manager" \
    "Gestionnaire de session — écran de login :" \
    "sddm"    "SDDM      — Qt/QML, recommandé pour KDE" \
    "gdm"     "GDM       — GNOME, recommandé pour GNOME" \
    "lightdm" "LightDM   — GTK, universel et léger" \
    "ly"      "Ly        — TUI terminal, minimal" \
    "greetd"  "greetd    — Daemon minimal + tuigreet" \
    "lxdm"    "LXDM      — LXDE, simple")
DISPLAY_MANAGER="${DISPLAY_MANAGER:-$_DM_DEFAULT}"

AUR_HELPER=$(d_menu "AUR Helper" \
    "Choisissez un AUR helper (requis pour certains paquets) :" \
    "yay"    "Go — le plus populaire (recommandé)" \
    "paru"   "Rust — fork de yay, rapide" \
    "trizen" "Perl — léger" \
    "none"   "Aucun — les paquets AUR ne seront pas installés")

if [[ "$AUR_HELPER" == "none" ]]; then
    d_msgbox "⚠️  AUR Helper désactivé" \
        "Sans AUR helper, les paquets suivants NE seront PAS installés :\n\n\
  • Brave       — Navigateur\n\
  • Heroic      — Launcher Epic/GOG\n\
  • Bottles     — Gestionnaire Wine\n\
  • Discord     — Chat\n\
  • Timeshift   — Snapshots système\n\
  • VSCode      — Éditeur de code\n\n\
Ces paquets peuvent être installés manuellement après le\n\
démarrage en installant yay/paru puis en lançant le script 2."
fi

_AUR_LABEL_SUFFIX=""
[[ "$AUR_HELPER" == "none" ]] && _AUR_LABEL_SUFFIX=" [AUR — IGNORÉ]" || _AUR_LABEL_SUFFIX=" (AUR)"

# ── Page 1 — Navigateurs ──────────────────────────────────
_SEL_NAV=$(d_checklist "🌐 Logiciels — Navigateurs (1/7)" \
    "Cochez les navigateurs à installer :" \
    "firefox"     "Firefox                      — Grand public, défaut"        "on"  \
    "chromium"    "Chromium                     — Open-source Chrome"          "off" \
    "brave"       "Brave${_AUR_LABEL_SUFFIX}    — Privacy + bloqueur pub"      "off" \
    "librewolf"   "LibreWolf${_AUR_LABEL_SUFFIX} — Firefox sans télémétrie"    "off" \
    "waterfox"    "Waterfox${_AUR_LABEL_SUFFIX} — Fork Firefox"                "off" \
    "zen-browser" "Zen${_AUR_LABEL_SUFFIX}      — Firefox tiling UI"           "off" \
    "vivaldi"     "Vivaldi${_AUR_LABEL_SUFFIX}  — Très personnalisable"        "off" \
    "opera"       "Opera${_AUR_LABEL_SUFFIX}    — VPN intégré"                 "off" \
    "falkon"      "Falkon                       — Léger, KDE natif"            "off" \
    "epiphany"    "Epiphany                     — GNOME Web, minimaliste"      "off" \
    "midori"      "Midori                       — Ultra léger"                 "off")

# ── Page 2 — Multimédia ───────────────────────────────────
_SEL_MEDIA=$(d_checklist "🎵 Logiciels — Multimédia (2/7)" \
    "Cochez les logiciels multimédia à installer :" \
    "vlc"         "VLC                          — Lecteur vidéo/audio"         "on"  \
    "mpv"         "MPV                          — Lecteur minimaliste"         "off" \
    "obs"         "OBS Studio                   — Streaming/Capture"           "on"  \
    "kdenlive"    "Kdenlive                     — Montage vidéo"               "off" \
    "handbrake"   "HandBrake                    — Encodage vidéo"              "off" \
    "audacity"    "Audacity                     — Édition audio"               "off" \
    "lmms"        "LMMS                         — Musique/DAW"                 "off" \
    "ardour"      "Ardour                       — DAW professionnel"           "off" \
    "blender"     "Blender                      — 3D/Animation"                "off" \
    "gimp"        "GIMP                         — Retouche photo"              "off" \
    "krita"       "Krita                        — Peinture numérique"          "off" \
    "inkscape"    "Inkscape                     — Dessin vectoriel"            "off" \
    "darktable"   "Darktable                    — Photo RAW (≈ Lightroom)"    "off" \
    "rawtherapee" "RawTherapee                  — Traitement RAW"              "off" \
    "digikam"     "digiKam                      — Gestion photos"              "off")

# ── Page 3 — Gaming ───────────────────────────────────────
_SEL_GAMING=$(d_checklist "🎮 Logiciels — Gaming (3/7)" \
    "Cochez les logiciels gaming à installer :" \
    "steam"       "Steam                        — Plateforme gaming"           "on"  \
    "lutris"      "Lutris                       — Launcher universel"          "on"  \
    "heroic"      "Heroic${_AUR_LABEL_SUFFIX}   — Epic/GOG/Amazon"             "off" \
    "gamemode"    "GameMode                     — Optimiseur CPU/GPU"          "on"  \
    "mangohud"    "MangoHud                     — Overlay FPS/GPU"             "on"  \
    "protonup"    "ProtonUp-Qt${_AUR_LABEL_SUFFIX} — Gestion Proton-GE"       "off" \
    "goverlay"    "GOverlay${_AUR_LABEL_SUFFIX} — GUI MangoHud/vkBasalt"      "off" \
    "vkbasalt"    "vkBasalt${_AUR_LABEL_SUFFIX} — Post-process shaders"       "off" \
    "bottles"     "Bottles${_AUR_LABEL_SUFFIX}  — Environnements Wine"         "off" \
    "discord"     "Discord${_AUR_LABEL_SUFFIX}  — Chat/Voix gaming"            "off")

# ── Page 4 — Émulateurs ───────────────────────────────────
_SEL_EMU=$(d_checklist "🕹️  Émulateurs (4/8)" \
    "Cochez les émulateurs à installer :" \
    \
    "retroarch"    "RetroArch                    — Frontend multi-systèmes"          "off" \
    "mednafen"     "Mednafen                     — Multi (PS1/Saturn/PC-Engine)"     "off" \
    "mame"         "MAME                         — Arcade"                           "off" \
    \
    "dolphin-emu"  "Dolphin                      — GameCube / Wii"                   "off" \
    "cemu"         "Cemu${_AUR_LABEL_SUFFIX}     — Wii U"                            "off" \
    "ryujinx"      "Ryujinx Canary${_AUR_LABEL_SUFFIX} — Nintendo Switch"           "off" \
    "sudachi"      "Sudachi${_AUR_LABEL_SUFFIX}  — Nintendo Switch (fork Yuzu)"      "off" \
    "mgba"         "mGBA                         — Game Boy / GBA"                   "off" \
    "sameboy"      "SameBoy                      — Game Boy / GBC"                   "off" \
    "bgb"          "BGB${_AUR_LABEL_SUFFIX}      — Game Boy / GBC (Wine)"            "off" \
    "melonds"      "melonDS${_AUR_LABEL_SUFFIX}  — Nintendo DS"                      "off" \
    "desmume"      "DeSmuME                      — Nintendo DS"                      "off" \
    "lime3ds"      "Lime3DS${_AUR_LABEL_SUFFIX}  — Nintendo 3DS (fork Citra)"        "off" \
    "azahar"       "Azahar${_AUR_LABEL_SUFFIX}   — Nintendo 3DS (successeur Citra)"  "off" \
    "snes9x"       "Snes9x                       — Super Nintendo"                   "off" \
    "fceux"        "FCEUX                        — NES / Famicom"                    "off" \
    "nestopia"     "Nestopia                     — NES / Famicom"                    "off" \
    "mupen64plus"  "Mupen64Plus                  — Nintendo 64"                      "off" \
    "simple64"     "simple64${_AUR_LABEL_SUFFIX} — Nintendo 64"                      "off" \
    \
    "pcsx2"        "PCSX2                        — PlayStation 2"                    "off" \
    "rpcs3"        "RPCS3${_AUR_LABEL_SUFFIX}    — PlayStation 3"                    "off" \
    "duckstation"  "DuckStation${_AUR_LABEL_SUFFIX} — PlayStation 1"                "off" \
    "ppsspp"       "PPSSPP                       — PSP"                              "off" \
    "shadps4"      "shadPS4${_AUR_LABEL_SUFFIX}  — PlayStation 4 (expérimental)"     "off" \
    "vita3k"       "Vita3K${_AUR_LABEL_SUFFIX}   — PlayStation Vita"                 "off" \
    \
    "xemu"         "xemu                         — Xbox original"                    "off" \
    "xenia"        "Xenia Canary${_AUR_LABEL_SUFFIX} — Xbox 360"                    "off" \
    \
    "flycast"      "Flycast${_AUR_LABEL_SUFFIX}  — Sega Dreamcast"                  "off" \
    "redream"      "Redream${_AUR_LABEL_SUFFIX}  — Sega Dreamcast"                  "off" \
    "stella"       "Stella                       — Atari 2600"                       "off" \
    \
    "scummvm"      "ScummVM                      — Jeux point & click"               "off" \
    "dosbox"       "DOSBox                       — DOS"                              "off" \
    "dosbox-x"     "DOSBox-X                     — DOS (compatible avancé)"          "off" \
    "dosbox-staging" "DOSBox Staging             — DOS (fork moderne)"               "off" \
    "vice"         "VICE                         — Commodore 64 / 128"               "off" \
    "openmsx"      "openMSX                      — MSX"                              "off" \
    "fs-uae"       "FS-UAE${_AUR_LABEL_SUFFIX}   — Commodore Amiga"                 "off" \
    "bizhawk"      "BizHawk${_AUR_LABEL_SUFFIX}  — Multi-systèmes (TAS)"            "off")

# ── Page 5 — Bureautique ──────────────────────────────────
_SEL_BUREAU=$(d_checklist "📋 Logiciels — Bureautique (5/8)" \
    "Cochez les logiciels de bureautique à installer :" \
    "libreoffice" "LibreOffice                  — Suite office"                "off" \
    "onlyoffice"  "OnlyOffice${_AUR_LABEL_SUFFIX} — Compat. MS Office"        "off" \
    "thunderbird" "Thunderbird                  — Messagerie email"            "off" \
    "signal"      "Signal${_AUR_LABEL_SUFFIX}   — Messagerie chiffrée"         "off" \
    "telegram"    "Telegram                     — Messagerie"                  "off" \
    "keepassxc"   "KeePassXC                    — Gestionnaire mots de passe"  "off" \
    "flameshot"   "Flameshot                    — Capture d'écran avancée"     "off" \
    "okular"      "Okular                       — Lecteur PDF/docs KDE"        "off" \
    "calibre"     "Calibre                      — Gestion ebooks"              "off" \
    "obsidian"    "Obsidian${_AUR_LABEL_SUFFIX} — Notes Markdown"              "off" \
    "gnome-disk"  "Gnome Disk Utility           — Gestionnaire de disques"     "on"  \
    "timeshift"   "Timeshift${_AUR_LABEL_SUFFIX} — Sauvegarde système"         "off")

# ── Page 6 — Développement & Sécurité ────────────────────
_SEL_DEV=$(d_checklist "🛠️  Logiciels — Dev & Sécurité (6/8)" \
    "Cochez les logiciels de développement et sécurité :" \
    "vscode"      "VSCode${_AUR_LABEL_SUFFIX}   — Éditeur de code"             "off" \
    "neovim"      "Neovim                       — Éditeur terminal"            "off" \
    "docker"      "Docker + Compose             — Conteneurs"                  "off" \
    "meld"        "Meld                         — Comparaison de fichiers"     "off" \
    "zsh"         "Zsh                          — Shell alternatif"            "off" \
    "ufw"         "UFW                          — Pare-feu simplifié"          "off" \
    "clamav"      "ClamAV                       — Antivirus open source"       "off" \
    "bleachbit"   "BleachBit                    — Nettoyage disque"            "off" \
    "veracrypt"   "VeraCrypt${_AUR_LABEL_SUFFIX} — Chiffrement volumes"        "off" \
    "btop"        "btop                         — Moniteur système avancé"     "off")

# ── Page 7 — Réseau & Performance ────────────────────────
_SEL_NET=$(d_checklist "📡 Logiciels — Réseau & Performance (7/8)" \
    "Cochez les logiciels réseau et performance :" \
    "qbittorrent" "qBittorrent                  — Client torrent"              "off" \
    "filezilla"   "FileZilla                    — FTP/SFTP"                    "off" \
    "remmina"     "Remmina                      — Bureau à distance RDP/VNC"   "off" \
    "wireshark"   "Wireshark                    — Analyse réseau"              "off" \
    "ananicy"     "Ananicy-cpp${_AUR_LABEL_SUFFIX} — Priorités processus"     "off" \
    "zram"        "zram-generator               — Swap RAM compressée"         "off" \
    "irqbalance"  "irqbalance                   — Distribution interruptions"  "off" \
    "power-profiles" "power-profiles-daemon     — Profils énergie CPU"         "off")

# Fusionner toutes les sélections
_PKG_SEL="$_SEL_NAV $_SEL_MEDIA $_SEL_GAMING $_SEL_EMU $_SEL_BUREAU $_SEL_DEV $_SEL_NET"

if [[ "$AUR_HELPER" == "none" ]]; then
    for _aur_pkg in brave librewolf waterfox zen-browser vivaldi opera heroic protonup goverlay vkbasalt bottles discord rpcs3 duckstation cemu ryujinx melonds bgb onlyoffice signal obsidian timeshift vscode ananicy veracrypt; do
        _PKG_SEL="${_PKG_SEL//$_aur_pkg/}"
    done
fi

_has_pkg() { [[ " $_PKG_SEL " == *" $1 "* ]]; }

# Navigateurs
PKG_FIREFOX=false;     _has_pkg firefox       && PKG_FIREFOX=true
PKG_CHROMIUM=false;    _has_pkg chromium      && PKG_CHROMIUM=true
PKG_BRAVE=false;       _has_pkg brave         && PKG_BRAVE=true
PKG_LIBREWOLF=false;   _has_pkg librewolf     && PKG_LIBREWOLF=true
PKG_WATERFOX=false;    _has_pkg waterfox      && PKG_WATERFOX=true
PKG_ZEN=false;         _has_pkg zen-browser   && PKG_ZEN=true
PKG_VIVALDI=false;     _has_pkg vivaldi       && PKG_VIVALDI=true
PKG_OPERA=false;       _has_pkg opera         && PKG_OPERA=true
PKG_FALKON=false;      _has_pkg falkon        && PKG_FALKON=true
PKG_EPIPHANY=false;    _has_pkg epiphany      && PKG_EPIPHANY=true
PKG_MIDORI=false;      _has_pkg midori        && PKG_MIDORI=true
# Multimédia
PKG_VLC=false;         _has_pkg vlc           && PKG_VLC=true
PKG_MPV=false;         _has_pkg mpv           && PKG_MPV=true
PKG_OBS=false;         _has_pkg obs           && PKG_OBS=true
PKG_KDENLIVE=false;    _has_pkg kdenlive      && PKG_KDENLIVE=true
PKG_HANDBRAKE=false;   _has_pkg handbrake     && PKG_HANDBRAKE=true
PKG_AUDACITY=false;    _has_pkg audacity      && PKG_AUDACITY=true
PKG_LMMS=false;        _has_pkg lmms          && PKG_LMMS=true
PKG_ARDOUR=false;      _has_pkg ardour        && PKG_ARDOUR=true
PKG_BLENDER=false;     _has_pkg blender       && PKG_BLENDER=true
PKG_GIMP=false;        _has_pkg gimp          && PKG_GIMP=true
PKG_KRITA=false;       _has_pkg krita         && PKG_KRITA=true
PKG_INKSCAPE=false;    _has_pkg inkscape      && PKG_INKSCAPE=true
PKG_DARKTABLE=false;   _has_pkg darktable     && PKG_DARKTABLE=true
PKG_RAWTHERAPEE=false; _has_pkg rawtherapee   && PKG_RAWTHERAPEE=true
PKG_DIGIKAM=false;     _has_pkg digikam       && PKG_DIGIKAM=true
# Gaming
PKG_STEAM=false;       _has_pkg steam         && PKG_STEAM=true
PKG_LUTRIS=false;      _has_pkg lutris        && PKG_LUTRIS=true
PKG_HEROIC=false;      _has_pkg heroic        && PKG_HEROIC=true
PKG_GAMEMODE=false;    _has_pkg gamemode      && PKG_GAMEMODE=true
PKG_MANGOHUD=false;    _has_pkg mangohud      && PKG_MANGOHUD=true
PKG_PROTONUP=false;    _has_pkg protonup      && PKG_PROTONUP=true
PKG_GOVERLAY=false;    _has_pkg goverlay      && PKG_GOVERLAY=true
PKG_VKBASALT=false;    _has_pkg vkbasalt      && PKG_VKBASALT=true
PKG_BOTTLES=false;     _has_pkg bottles       && PKG_BOTTLES=true
PKG_DISCORD=false;     _has_pkg discord       && PKG_DISCORD=true
# Émulateurs
# Émulateurs — multi-systèmes
PKG_RETROARCH=false;    _has_pkg retroarch      && PKG_RETROARCH=true
PKG_MEDNAFEN=false;     _has_pkg mednafen       && PKG_MEDNAFEN=true
PKG_MAME=false;         _has_pkg mame           && PKG_MAME=true
PKG_BIZHAWK=false;      _has_pkg bizhawk        && PKG_BIZHAWK=true
# Nintendo
PKG_DOLPHIN=false;      _has_pkg dolphin-emu    && PKG_DOLPHIN=true
PKG_CEMU=false;         _has_pkg cemu           && PKG_CEMU=true
PKG_RYUJINX=false;      _has_pkg ryujinx        && PKG_RYUJINX=true
PKG_SUDACHI=false;      _has_pkg sudachi        && PKG_SUDACHI=true
PKG_MGBA=false;         _has_pkg mgba           && PKG_MGBA=true
PKG_SAMEBOY=false;      _has_pkg sameboy        && PKG_SAMEBOY=true
PKG_BGB=false;          _has_pkg bgb            && PKG_BGB=true
PKG_MELONDS=false;      _has_pkg melonds        && PKG_MELONDS=true
PKG_DESMUME=false;      _has_pkg desmume        && PKG_DESMUME=true
PKG_LIME3DS=false;      _has_pkg lime3ds        && PKG_LIME3DS=true
PKG_AZAHAR=false;       _has_pkg azahar         && PKG_AZAHAR=true
PKG_SNES9X=false;       _has_pkg snes9x         && PKG_SNES9X=true
PKG_FCEUX=false;        _has_pkg fceux          && PKG_FCEUX=true
PKG_NESTOPIA=false;     _has_pkg nestopia       && PKG_NESTOPIA=true
PKG_MUPEN64=false;      _has_pkg mupen64plus    && PKG_MUPEN64=true
PKG_SIMPLE64=false;     _has_pkg simple64       && PKG_SIMPLE64=true
# Sony
PKG_PCSX2=false;        _has_pkg pcsx2          && PKG_PCSX2=true
PKG_RPCS3=false;        _has_pkg rpcs3          && PKG_RPCS3=true
PKG_DUCKSTATION=false;  _has_pkg duckstation    && PKG_DUCKSTATION=true
PKG_PPSSPP=false;       _has_pkg ppsspp         && PKG_PPSSPP=true
PKG_SHADPS4=false;      _has_pkg shadps4        && PKG_SHADPS4=true
PKG_VITA3K=false;       _has_pkg vita3k         && PKG_VITA3K=true
# Microsoft
PKG_XEMU=false;         _has_pkg xemu           && PKG_XEMU=true
PKG_XENIA=false;        _has_pkg xenia          && PKG_XENIA=true
# Sega / Atari
PKG_FLYCAST=false;      _has_pkg flycast        && PKG_FLYCAST=true
PKG_REDREAM=false;      _has_pkg redream        && PKG_REDREAM=true
PKG_STELLA=false;       _has_pkg stella         && PKG_STELLA=true
# PC / Multi
PKG_SCUMMVM=false;      _has_pkg scummvm        && PKG_SCUMMVM=true
PKG_DOSBOX=false;       _has_pkg dosbox         && PKG_DOSBOX=true
PKG_DOSBOX_X=false;     _has_pkg dosbox-x       && PKG_DOSBOX_X=true
PKG_DOSBOX_S=false;     _has_pkg dosbox-staging && PKG_DOSBOX_S=true
PKG_VICE=false;         _has_pkg vice           && PKG_VICE=true
PKG_OPENMSX=false;      _has_pkg openmsx        && PKG_OPENMSX=true
PKG_FSUAE=false;        _has_pkg fs-uae         && PKG_FSUAE=true
# Bureautique
PKG_LIBREOFFICE=false; _has_pkg libreoffice   && PKG_LIBREOFFICE=true
PKG_ONLYOFFICE=false;  _has_pkg onlyoffice    && PKG_ONLYOFFICE=true
PKG_THUNDERBIRD=false; _has_pkg thunderbird   && PKG_THUNDERBIRD=true
PKG_SIGNAL=false;      _has_pkg signal        && PKG_SIGNAL=true
PKG_TELEGRAM=false;    _has_pkg telegram      && PKG_TELEGRAM=true
PKG_KEEPASSXC=false;   _has_pkg keepassxc     && PKG_KEEPASSXC=true
PKG_FLAMESHOT=false;   _has_pkg flameshot     && PKG_FLAMESHOT=true
PKG_OKULAR=false;      _has_pkg okular        && PKG_OKULAR=true
PKG_CALIBRE=false;     _has_pkg calibre       && PKG_CALIBRE=true
PKG_OBSIDIAN=false;    _has_pkg obsidian      && PKG_OBSIDIAN=true
PKG_GNOME_DISK=false;  _has_pkg gnome-disk    && PKG_GNOME_DISK=true
PKG_TIMESHIFT=false;   _has_pkg timeshift     && PKG_TIMESHIFT=true
# Développement
PKG_VSCODE=false;      _has_pkg vscode        && PKG_VSCODE=true
PKG_NEOVIM=false;      _has_pkg neovim        && PKG_NEOVIM=true
PKG_DOCKER=false;      _has_pkg docker        && PKG_DOCKER=true
PKG_MELD=false;        _has_pkg meld          && PKG_MELD=true
PKG_ZSH=false;         _has_pkg zsh           && PKG_ZSH=true
# Sécurité
PKG_UFW=false;         _has_pkg ufw           && PKG_UFW=true
PKG_CLAMAV=false;      _has_pkg clamav        && PKG_CLAMAV=true
PKG_BLEACHBIT=false;   _has_pkg bleachbit     && PKG_BLEACHBIT=true
PKG_VERACRYPT=false;   _has_pkg veracrypt     && PKG_VERACRYPT=true
PKG_BTOP=false;        _has_pkg btop          && PKG_BTOP=true
# Performance
PKG_ANANICY=false;     _has_pkg ananicy       && PKG_ANANICY=true
PKG_ZRAM=false;        _has_pkg zram          && PKG_ZRAM=true
PKG_IRQBALANCE=false;  _has_pkg irqbalance    && PKG_IRQBALANCE=true
PKG_PPD=false;         _has_pkg power-profiles && PKG_PPD=true
# Réseau
PKG_QBITTORRENT=false; _has_pkg qbittorrent   && PKG_QBITTORRENT=true
PKG_FILEZILLA=false;   _has_pkg filezilla     && PKG_FILEZILLA=true
PKG_REMMINA=false;     _has_pkg remmina       && PKG_REMMINA=true
PKG_WIRESHARK=false;   _has_pkg wireshark     && PKG_WIRESHARK=true

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
    if [[ -z "$ROOT_PASS" ]]; then
        d_msgbox "Erreur" "Le mot de passe root ne peut pas être vide. Réessayez."
        continue
    fi
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
    if [[ -z "$USER_PASS" ]]; then
        d_msgbox "Erreur" "Le mot de passe de $USERNAME ne peut pas être vide. Réessayez."
        continue
    fi
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

# ── Taille du swapfile ────────────────────────────────────
_RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
_SWAP_SUGGESTED=$(( _RAM_GB <= 4 ? _RAM_GB * 2 : _RAM_GB <= 16 ? _RAM_GB : 16 ))
SWAP_SIZE=$(d_menu "Taille du Swapfile" \
    "RAM détectée : ${_RAM_GB} Go — Recommandation : ${_SWAP_SUGGESTED} Go :" \
    "0"  "Aucun swap" \
    "2"  "2 Go" \
    "4"  "4 Go" \
    "8"  "8 Go  (recommandé si RAM ≤ 8 Go)" \
    "16" "16 Go (recommandé si RAM > 8 Go)" \
    "32" "32 Go")
SWAP_SIZE="${SWAP_SIZE:-$_SWAP_SUGGESTED}"

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
d_progress_box "🌐 Miroirs — Sélection en cours..." \
    bash -c "reflector --country France --age 12 --protocol https --sort rate \
        --timeout 5 --latest 20 \
        --save /etc/pacman.d/mirrorlist 2>&1 \
        || echo 'reflector échoué — miroirs par défaut conservés'
    SELECTED=\$(grep '^Server' /etc/pacman.d/mirrorlist | head -1 | sed 's/Server = //')
    echo \"Miroir retenu : \$SELECTED\"" || true

# ── Sync DB & résolution des dépendances ─────────────────
d_progress_box "🔍 Résolution des dépendances..." \
    bash -c "pacman -Sy 2>&1 && echo 'Base de données synchronisée'" || true

_UCODE_PKG=""
if ! $_IS_VM; then
    [[ "$_CPU" == "intel" ]] && _UCODE_PKG="intel-ucode" || _UCODE_PKG="amd-ucode"
fi

# Construire la liste de paquets base
_PKGS_BASE=()
for _p in base base-devel ${KERNELS} linux-firmware \
           ${_UCODE_PKG} networkmanager grub efibootmgr \
           nano vim git curl wget gptfdisk; do
    [[ -n "$_p" ]] && _PKGS_BASE+=("$_p")
done

# Dry-run pour le total — protégé contre les erreurs
_TOTAL_BASE=$(pacman -Sp --print-format '%n' "${_PKGS_BASE[@]}" 2>/dev/null | wc -l) || true
[[ -z "$_TOTAL_BASE" || "$_TOTAL_BASE" -lt 1 ]] && _TOTAL_BASE=0

export _DB_SYNCED=true

# ── pacstrap ─────────────────────────────────────────────

pacstrap_gauge "📦 Base système — pacstrap" /mnt \
    "${_PKGS_BASE[@]}"

# ── fstab ─────────────────────────────────────────────────
d_run_gauge 5 "Configuration" "Génération du fstab..." \
    bash -c "genfstab -U /mnt >> /mnt/etc/fstab"

# Sync DB dans le chroot pour les futures résolutions
arch-chroot /mnt pacman -Sy &>/dev/null || true

# ══════════════════════════════════════════════════════════
#  CONFIGURATION (CHROOT) — partie 1 : système de base
#  Timezone, locale, hostname, users, keyboard, GRUB, multilib
# ══════════════════════════════════════════════════════════
_CHROOT_CFG=$(mktemp /mnt/root/chroot-cfg-XXXXXX.sh)
chmod +x "$_CHROOT_CFG"

cat > "$_CHROOT_CFG" << 'CHROOT_CFG_EOF'
#!/bin/bash
set -uo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "\n${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
banner()  { echo -e "\n${BOLD}══ $1 ══${NC}"; }
CHROOT_CFG_EOF

# Inject variables (not using single-quoted heredoc above so we can expand here)
cat >> "$_CHROOT_CFG" << CHROOT_CFG_VARS
TIMEZONE="${TIMEZONE}"
LOCALE="${LOCALE}"
KEYMAP="${KEYMAP}"
HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
ROOT_PASS="${ROOT_PASS}"
USER_PASS="${USER_PASS}"
_IS_VM="${_IS_VM}"
_OPTIMUS="${_OPTIMUS}"
INSTALL_KDE="${INSTALL_KDE}"
INSTALL_GNOME="${INSTALL_GNOME}"
INSTALL_XFCE="${INSTALL_XFCE}"
INSTALL_CINNAMON="${INSTALL_CINNAMON}"
INSTALL_MATE="${INSTALL_MATE}"
INSTALL_BUDGIE="${INSTALL_BUDGIE}"
INSTALL_LXQT="${INSTALL_LXQT}"
INSTALL_OPENBOX="${INSTALL_OPENBOX}"
INSTALL_I3="${INSTALL_I3}"
INSTALL_SWAY="${INSTALL_SWAY}"
INSTALL_HYPRLAND="${INSTALL_HYPRLAND}"
INSTALL_BSPWM="${INSTALL_BSPWM}"
INSTALL_AWESOME="${INSTALL_AWESOME}"
DISPLAY_MANAGER="${DISPLAY_MANAGER}"
SWAP_SIZE="${SWAP_SIZE}"
CHROOT_CFG_VARS

cat >> "$_CHROOT_CFG" << 'CHROOT_CFG_BODY'

banner "TIMEZONE"
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
success "Timezone : ${TIMEZONE}"

banner "LOCALE"
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
success "Locale : ${LOCALE} — Clavier : ${KEYMAP}"

banner "HOSTNAME"
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
success "Hostname : ${HOSTNAME}"

banner "UTILISATEURS"
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
success "Utilisateurs créés"

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

banner "GRUB"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3600/' /etc/default/grub
sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
sed -i 's/^#\?GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080x32/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
success "GRUB installé"

banner "MULTILIB"
sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf
pacman -Sy --noconfirm
success "Dépôt multilib activé"

rm -f "$0"
CHROOT_CFG_BODY

d_progress_box "⚙️  Configuration de base (chroot)" \
    arch-chroot /mnt /bin/bash "${_CHROOT_CFG#/mnt}" || true

# ══════════════════════════════════════════════════════════
#  INSTALLATION DES PAQUETS — depuis l'hôte avec jauge
#  arch-chroot pacman est appelé depuis l'hôte ; le cache
#  /mnt/var/cache/pacman/pkg/ est surveillé pour la jauge.
# ══════════════════════════════════════════════════════════

# Helper: run pacman inside chroot with a download progress gauge
# chroot_pacman_gauge <title> <pkg1> [pkg2 ...]
chroot_pacman_gauge() {
    local title="$1"; shift
    local pkgs=()
    for p in "$@"; do [[ -n "$p" ]] && pkgs+=("$p"); done
    _cache_gauge "$title" \
        /mnt/var/cache/pacman/pkg \
        /mnt/var/lib/pacman/local \
        arch-chroot /mnt pacman -S --noconfirm --disable-download-timeout "${pkgs[@]}"
}

banner "DRIVERS GPU"
if $_IS_VM; then
    chroot_pacman_gauge "Drivers VMware" \
        mesa xf86-input-vmmouse xf86-video-fbdev vulkan-icd-loader open-vm-tools

elif $_NEED_NVIDIA && $_NEED_AMD_GPU; then
    chroot_pacman_gauge "Drivers Optimus — AMD" \
        mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu
    chroot_pacman_gauge "Drivers Optimus — NVIDIA" \
        nvidia nvidia-utils nvidia-settings lib32-nvidia-utils lib32-mesa
    chroot_pacman_gauge "Drivers Optimus — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader
    arch-chroot /mnt bash -c '
        echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
        sed -i "s/^MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/" /etc/mkinitcpio.conf
        mkinitcpio -P'
    chroot_pacman_gauge "Drivers Optimus — switcheroo" switcheroo-control

elif $_NEED_NVIDIA; then
    chroot_pacman_gauge "Drivers NVIDIA" \
        nvidia nvidia-utils nvidia-settings lib32-nvidia-utils lib32-mesa
    chroot_pacman_gauge "Drivers NVIDIA — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader
    arch-chroot /mnt bash -c '
        echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
        sed -i "s/^MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/" /etc/mkinitcpio.conf
        mkinitcpio -P'

elif $_NEED_AMD_GPU; then
    chroot_pacman_gauge "Drivers AMD GPU" \
        mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu \
        lib32-mesa lib32-vulkan-radeon
    chroot_pacman_gauge "Drivers AMD GPU — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader

else
    chroot_pacman_gauge "Drivers Intel iGPU" \
        mesa vulkan-intel intel-media-driver lib32-mesa lib32-vulkan-intel
    chroot_pacman_gauge "Drivers Intel — Vulkan" \
        vulkan-icd-loader lib32-vulkan-icd-loader
fi

chroot_pacman_gauge "Pipewire — audio" \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

$INSTALL_KDE      && chroot_pacman_gauge "KDE Plasma" \
    plasma-meta dolphin konsole kate ark gwenview okular spectacle yakuake
$INSTALL_GNOME    && chroot_pacman_gauge "GNOME" gnome gnome-extra
$INSTALL_CINNAMON && chroot_pacman_gauge "Cinnamon" cinnamon
$INSTALL_MATE     && chroot_pacman_gauge "MATE" mate mate-extra
$INSTALL_BUDGIE   && chroot_pacman_gauge "Budgie" budgie-desktop budgie-extras
$INSTALL_LXQT     && chroot_pacman_gauge "LXQt" lxqt breeze-icons
$INSTALL_XFCE     && chroot_pacman_gauge "XFCE4" xfce4 xfce4-goodies
$INSTALL_OPENBOX  && chroot_pacman_gauge "Openbox" openbox obconf tint2 feh picom
$INSTALL_I3       && chroot_pacman_gauge "i3" i3-wm i3status i3lock dmenu feh picom
$INSTALL_SWAY     && chroot_pacman_gauge "Sway" sway swaylock swayidle waybar wofi mako
$INSTALL_HYPRLAND && chroot_pacman_gauge "Hyprland" hyprland waybar wofi mako \
    hyprpaper xdg-desktop-portal-hyprland
$INSTALL_BSPWM    && chroot_pacman_gauge "BSPWM" bspwm sxhkd rofi picom feh polybar
$INSTALL_AWESOME  && chroot_pacman_gauge "AwesomeWM" awesome rofi picom feh

# ── Display Manager ────────────────────────────────────────
case "${DISPLAY_MANAGER}" in
    sddm)
        chroot_pacman_gauge "SDDM" sddm
        arch-chroot /mnt systemctl enable sddm ;;
    gdm)
        chroot_pacman_gauge "GDM" gdm
        arch-chroot /mnt systemctl enable gdm ;;
    lightdm)
        chroot_pacman_gauge "LightDM" lightdm lightdm-gtk-greeter
        arch-chroot /mnt systemctl enable lightdm ;;
    ly)
        chroot_pacman_gauge "Ly" ly
        arch-chroot /mnt systemctl enable ly ;;
    greetd)
        chroot_pacman_gauge "greetd" greetd greetd-tuigreet
        arch-chroot /mnt systemctl enable greetd ;;
    lxdm)
        chroot_pacman_gauge "LXDM" lxdm
        arch-chroot /mnt systemctl enable lxdm ;;
esac
success "Display Manager : ${DISPLAY_MANAGER} activé"

if [[ "$AUR_HELPER" != "none" ]]; then
    # Dépendances communes
    chroot_pacman_gauge "AUR Helper — dépendances de base" go git base-devel

    # Dépendances spécifiques selon le helper
    case "$AUR_HELPER" in
        paru)
            chroot_pacman_gauge "AUR Helper — dépendances paru (Rust)" rust cargo ;;
        trizen)
            chroot_pacman_gauge "AUR Helper — dépendances trizen (Perl)" \
                perl perl-lwp-protocol-https perl-term-ui perl-json ;;
    esac

    d_progress_box "AUR Helper — ${AUR_HELPER}" \
        arch-chroot /mnt bash -c "
            set -e

            # NOPASSWD temporaire pour que makepkg puisse appeler pacman
            echo '${USERNAME} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/aur-build-tmp
            chmod 440 /etc/sudoers.d/aur-build-tmp

            # Nettoyer un éventuel clone précédent
            rm -rf /tmp/${AUR_HELPER}

            # Cloner
            cd /tmp
            git clone https://aur.archlinux.org/${AUR_HELPER}.git
            chown -R '${USERNAME}':'${USERNAME}' /tmp/${AUR_HELPER}

            # Compiler et installer en tant que non-root
            su - '${USERNAME}' -c 'cd /tmp/${AUR_HELPER} && makepkg -si --noconfirm --needed'

            # Retirer le NOPASSWD temporaire
            rm -f /etc/sudoers.d/aur-build-tmp

            # Nettoyage
            rm -rf /tmp/${AUR_HELPER}
            echo '${AUR_HELPER} installé avec succès'" || true
fi

# Build pacman package list
_PACMAN_PKGS="htop fastfetch"
_AUR_PKGS=""

# Navigateurs
$PKG_FIREFOX     && _PACMAN_PKGS="$_PACMAN_PKGS firefox"
$PKG_CHROMIUM    && _PACMAN_PKGS="$_PACMAN_PKGS chromium"
$PKG_BRAVE       && _AUR_PKGS="$_AUR_PKGS brave-bin"
$PKG_LIBREWOLF   && _AUR_PKGS="$_AUR_PKGS librewolf-bin"
$PKG_WATERFOX    && _AUR_PKGS="$_AUR_PKGS waterfox-g-bin"
$PKG_ZEN         && _AUR_PKGS="$_AUR_PKGS zen-browser-bin"
$PKG_VIVALDI     && _AUR_PKGS="$_AUR_PKGS vivaldi"
$PKG_OPERA       && _AUR_PKGS="$_AUR_PKGS opera"
$PKG_FALKON      && _PACMAN_PKGS="$_PACMAN_PKGS falkon"
$PKG_EPIPHANY    && _PACMAN_PKGS="$_PACMAN_PKGS epiphany"
$PKG_MIDORI      && _PACMAN_PKGS="$_PACMAN_PKGS midori"
# Multimédia
$PKG_VLC         && _PACMAN_PKGS="$_PACMAN_PKGS vlc"
$PKG_MPV         && _PACMAN_PKGS="$_PACMAN_PKGS mpv"
$PKG_OBS         && _PACMAN_PKGS="$_PACMAN_PKGS obs-studio"
$PKG_KDENLIVE    && _PACMAN_PKGS="$_PACMAN_PKGS kdenlive"
$PKG_HANDBRAKE   && _PACMAN_PKGS="$_PACMAN_PKGS handbrake"
$PKG_AUDACITY    && _PACMAN_PKGS="$_PACMAN_PKGS audacity"
$PKG_LMMS        && _PACMAN_PKGS="$_PACMAN_PKGS lmms"
$PKG_ARDOUR      && _PACMAN_PKGS="$_PACMAN_PKGS ardour"
$PKG_BLENDER     && _PACMAN_PKGS="$_PACMAN_PKGS blender"
$PKG_GIMP        && _PACMAN_PKGS="$_PACMAN_PKGS gimp"
$PKG_KRITA       && _PACMAN_PKGS="$_PACMAN_PKGS krita"
$PKG_INKSCAPE    && _PACMAN_PKGS="$_PACMAN_PKGS inkscape"
$PKG_DARKTABLE   && _PACMAN_PKGS="$_PACMAN_PKGS darktable"
$PKG_RAWTHERAPEE && _PACMAN_PKGS="$_PACMAN_PKGS rawtherapee"
$PKG_DIGIKAM     && _PACMAN_PKGS="$_PACMAN_PKGS digikam"
# Gaming
$PKG_STEAM       && _PACMAN_PKGS="$_PACMAN_PKGS steam"
$PKG_LUTRIS      && _PACMAN_PKGS="$_PACMAN_PKGS lutris"
$PKG_HEROIC      && _AUR_PKGS="$_AUR_PKGS heroic-games-launcher-bin"
$PKG_GAMEMODE    && _PACMAN_PKGS="$_PACMAN_PKGS gamemode lib32-gamemode"
$PKG_MANGOHUD    && _PACMAN_PKGS="$_PACMAN_PKGS mangohud lib32-mangohud"
$PKG_PROTONUP    && _AUR_PKGS="$_AUR_PKGS protonup-qt"
$PKG_GOVERLAY    && _AUR_PKGS="$_AUR_PKGS goverlay"
$PKG_VKBASALT    && _AUR_PKGS="$_AUR_PKGS vkbasalt"
$PKG_BOTTLES     && _AUR_PKGS="$_AUR_PKGS bottles"
$PKG_DISCORD     && _AUR_PKGS="$_AUR_PKGS discord"
# Émulateurs
# Émulateurs — pacman
$PKG_RETROARCH   && _PACMAN_PKGS="$_PACMAN_PKGS retroarch retroarch-assets-xmb"
$PKG_MEDNAFEN    && _PACMAN_PKGS="$_PACMAN_PKGS mednafen"
$PKG_MAME        && _PACMAN_PKGS="$_PACMAN_PKGS mame"
$PKG_DOLPHIN     && _PACMAN_PKGS="$_PACMAN_PKGS dolphin-emu"
$PKG_PCSX2       && _PACMAN_PKGS="$_PACMAN_PKGS pcsx2"
$PKG_PPSSPP      && _PACMAN_PKGS="$_PACMAN_PKGS ppsspp"
$PKG_MGBA        && _PACMAN_PKGS="$_PACMAN_PKGS mgba-qt"
$PKG_SAMEBOY     && _AUR_PKGS="$_AUR_PKGS sameboy"
$PKG_DESMUME     && _PACMAN_PKGS="$_PACMAN_PKGS desmume"
$PKG_SNES9X      && _PACMAN_PKGS="$_PACMAN_PKGS snes9x-gtk"
$PKG_FCEUX       && _PACMAN_PKGS="$_PACMAN_PKGS fceux"
$PKG_NESTOPIA    && _AUR_PKGS="$_AUR_PKGS nestopia-ue"
$PKG_MUPEN64     && _PACMAN_PKGS="$_PACMAN_PKGS mupen64plus"
$PKG_XEMU        && _PACMAN_PKGS="$_PACMAN_PKGS xemu"
$PKG_STELLA      && _PACMAN_PKGS="$_PACMAN_PKGS stella"
$PKG_SCUMMVM     && _PACMAN_PKGS="$_PACMAN_PKGS scummvm"
$PKG_DOSBOX      && _PACMAN_PKGS="$_PACMAN_PKGS dosbox"
$PKG_DOSBOX_S    && _PACMAN_PKGS="$_PACMAN_PKGS dosbox-staging"
$PKG_VICE        && _PACMAN_PKGS="$_PACMAN_PKGS vice"
$PKG_OPENMSX     && _PACMAN_PKGS="$_PACMAN_PKGS openmsx"
# Émulateurs — AUR
$PKG_CEMU        && _AUR_PKGS="$_AUR_PKGS cemu-bin"
$PKG_RYUJINX     && _AUR_PKGS="$_AUR_PKGS ryujinx-canary"
$PKG_SUDACHI     && _AUR_PKGS="$_AUR_PKGS sudachi-bin"
$PKG_MELONDS     && _AUR_PKGS="$_AUR_PKGS melonds-bin"
$PKG_LIME3DS     && _AUR_PKGS="$_AUR_PKGS lime3ds-bin"
$PKG_AZAHAR      && _AUR_PKGS="$_AUR_PKGS azahar"
$PKG_SIMPLE64    && _AUR_PKGS="$_AUR_PKGS simple64-bin"
$PKG_RPCS3       && _AUR_PKGS="$_AUR_PKGS rpcs3-bin"
$PKG_DUCKSTATION && _AUR_PKGS="$_AUR_PKGS duckstation-qt-bin"
$PKG_SHADPS4     && _AUR_PKGS="$_AUR_PKGS shadps4-bin"
$PKG_VITA3K      && _AUR_PKGS="$_AUR_PKGS vita3k-bin"
$PKG_XENIA       && _AUR_PKGS="$_AUR_PKGS xenia-canary-bin"
$PKG_FLYCAST     && _AUR_PKGS="$_AUR_PKGS flycast-bin"
$PKG_REDREAM     && _AUR_PKGS="$_AUR_PKGS redream"
$PKG_DOSBOX_X    && _AUR_PKGS="$_AUR_PKGS dosbox-x"
$PKG_FSUAE       && _AUR_PKGS="$_AUR_PKGS fs-uae"
$PKG_BIZHAWK     && _AUR_PKGS="$_AUR_PKGS bizhawk-bin"
$PKG_BGB         && _AUR_PKGS="$_AUR_PKGS bgb"
$PKG_RPCS3       && _AUR_PKGS="$_AUR_PKGS rpcs3-bin"
$PKG_DUCKSTATION && _AUR_PKGS="$_AUR_PKGS duckstation-qt-bin"
$PKG_PPSSPP      && _PACMAN_PKGS="$_PACMAN_PKGS ppsspp"
$PKG_CEMU        && _AUR_PKGS="$_AUR_PKGS cemu-bin"
$PKG_RYUJINX     && _AUR_PKGS="$_AUR_PKGS ryujinx-canary"
$PKG_MGBA        && _PACMAN_PKGS="$_PACMAN_PKGS mgba-qt"
$PKG_MELONDS     && _AUR_PKGS="$_AUR_PKGS melonds-bin"
$PKG_BGB         && _AUR_PKGS="$_AUR_PKGS bgb"
$PKG_DOSBOX      && _PACMAN_PKGS="$_PACMAN_PKGS dosbox"
$PKG_SCUMMVM     && _PACMAN_PKGS="$_PACMAN_PKGS scummvm"
$PKG_XEMU        && _PACMAN_PKGS="$_PACMAN_PKGS xemu"
# Bureautique
$PKG_LIBREOFFICE && _PACMAN_PKGS="$_PACMAN_PKGS libreoffice-fresh"
$PKG_ONLYOFFICE  && _AUR_PKGS="$_AUR_PKGS onlyoffice-bin"
$PKG_THUNDERBIRD && _PACMAN_PKGS="$_PACMAN_PKGS thunderbird"
$PKG_SIGNAL      && _AUR_PKGS="$_AUR_PKGS signal-desktop"
$PKG_TELEGRAM    && _PACMAN_PKGS="$_PACMAN_PKGS telegram-desktop"
$PKG_KEEPASSXC   && _PACMAN_PKGS="$_PACMAN_PKGS keepassxc"
$PKG_FLAMESHOT   && _PACMAN_PKGS="$_PACMAN_PKGS flameshot"
$PKG_OKULAR      && _PACMAN_PKGS="$_PACMAN_PKGS okular"
$PKG_CALIBRE     && _PACMAN_PKGS="$_PACMAN_PKGS calibre"
$PKG_OBSIDIAN    && _AUR_PKGS="$_AUR_PKGS obsidian"
$PKG_GNOME_DISK  && _PACMAN_PKGS="$_PACMAN_PKGS gnome-disk-utility"
$PKG_TIMESHIFT   && _AUR_PKGS="$_AUR_PKGS timeshift"
# Développement
$PKG_VSCODE      && _AUR_PKGS="$_AUR_PKGS visual-studio-code-bin"
$PKG_NEOVIM      && _PACMAN_PKGS="$_PACMAN_PKGS neovim"
$PKG_DOCKER      && _PACMAN_PKGS="$_PACMAN_PKGS docker docker-compose"
$PKG_MELD        && _PACMAN_PKGS="$_PACMAN_PKGS meld"
$PKG_ZSH         && _PACMAN_PKGS="$_PACMAN_PKGS zsh"
# Sécurité
$PKG_UFW         && _PACMAN_PKGS="$_PACMAN_PKGS ufw"
$PKG_CLAMAV      && _PACMAN_PKGS="$_PACMAN_PKGS clamav"
$PKG_BLEACHBIT   && _PACMAN_PKGS="$_PACMAN_PKGS bleachbit"
$PKG_VERACRYPT   && _AUR_PKGS="$_AUR_PKGS veracrypt"
$PKG_BTOP        && _PACMAN_PKGS="$_PACMAN_PKGS btop"
# Performance
$PKG_ANANICY     && _AUR_PKGS="$_AUR_PKGS ananicy-cpp"
$PKG_ZRAM        && _PACMAN_PKGS="$_PACMAN_PKGS zram-generator"
$PKG_IRQBALANCE  && _PACMAN_PKGS="$_PACMAN_PKGS irqbalance"
$PKG_PPD         && _PACMAN_PKGS="$_PACMAN_PKGS power-profiles-daemon"
# Réseau
$PKG_QBITTORRENT && _PACMAN_PKGS="$_PACMAN_PKGS qbittorrent"
$PKG_FILEZILLA   && _PACMAN_PKGS="$_PACMAN_PKGS filezilla"
$PKG_REMMINA     && _PACMAN_PKGS="$_PACMAN_PKGS remmina"
$PKG_WIRESHARK   && _PACMAN_PKGS="$_PACMAN_PKGS wireshark-qt"

chroot_pacman_gauge "Logiciels supplémentaires" ${_PACMAN_PKGS}

$PKG_DOCKER && arch-chroot /mnt systemctl enable docker 2>/dev/null || true

if [[ -n "${_AUR_PKGS## }" && "$AUR_HELPER" != "none" ]]; then
    d_progress_box "Paquets AUR" \
        arch-chroot /mnt bash -c "
            # NOPASSWD pour que le helper puisse appeler sudo pacman
            echo '${USERNAME} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/aur-install-tmp
            chmod 440 /etc/sudoers.d/aur-install-tmp

            su - '${USERNAME}' -c '${AUR_HELPER} -S --noconfirm --mflags \"--nocheck\" ${_AUR_PKGS}'

            # Retirer le NOPASSWD après installation
            rm -f /etc/sudoers.d/aur-install-tmp" || true
fi

# ══════════════════════════════════════════════════════════
#  CONFIGURATION (CHROOT) — partie 2 : post-install
#  SDDM, clavier KDE, services, swapfile
# ══════════════════════════════════════════════════════════
_CHROOT_POST=$(mktemp /mnt/root/chroot-post-XXXXXX.sh)
chmod +x "$_CHROOT_POST"

cat > "$_CHROOT_POST" << 'CHROOT_POST_EOF'
#!/bin/bash
set -uo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
success() { echo -e "${GREEN}[OK]${NC} $1"; }
banner()  { echo -e "\n${BOLD}══ $1 ══${NC}"; }
CHROOT_POST_EOF

cat >> "$_CHROOT_POST" << CHROOT_POST_VARS
USERNAME="${USERNAME}"
KEYMAP="${KEYMAP}"
_IS_VM="${_IS_VM}"
_OPTIMUS="${_OPTIMUS}"
DISPLAY_MANAGER="${DISPLAY_MANAGER}"
SWAP_SIZE="${SWAP_SIZE}"
CHROOT_POST_VARS

cat >> "$_CHROOT_POST" << 'CHROOT_POST_BODY'

banner "DISPLAY MANAGER"
case "${DISPLAY_MANAGER}" in
    sddm)
        if systemctl cat sddm.service &>/dev/null; then
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
            systemctl enable sddm
            success "SDDM configuré et activé"
        else
            warn "SDDM non installé — activation ignorée"
        fi
        ;;
    lightdm)
        systemctl enable lightdm 2>/dev/null && success "LightDM activé" || warn "LightDM non installé"
        ;;
    gdm)
        systemctl enable gdm 2>/dev/null && success "GDM activé" || warn "GDM non installé"
        ;;
esac

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

banner "SWAPFILE"
if [[ "${SWAP_SIZE}" -gt 0 ]]; then
    dd if=/dev/zero of=/swapfile bs=1M count=$(( SWAP_SIZE * 1024 )) status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
    success "Swapfile ${SWAP_SIZE} Go créé"
else
    success "Swap désactivé — aucun swapfile créé"
fi
success "Swapfile 8 Go créé"

rm -f "$0"
CHROOT_POST_BODY

d_progress_box "⚙️  Configuration post-install (chroot)" \
    arch-chroot /mnt /bin/bash "${_CHROOT_POST#/mnt}" || true

# ── Démontage final ───────────────────────────────────────
d_run_gauge 95 "Finalisation" "Démontage des partitions..." bash -c "
    sync
    umount -R -l /mnt
"

# ══════════════════════════════════════════════════════════
#  FIN
# ══════════════════════════════════════════════════════════

# Fermer proprement le pipe tee pour vider les buffers
exec 1>&- 2>&-
sleep 0.5

# Copie du log dans le système installé
if mountpoint -q /mnt 2>/dev/null; then
    cp "$LOG_FILE" /mnt/root/ais.log 2>/dev/null || true
fi

# Message de fin sur /dev/tty directement
_OPT_MSG=""
[[ "$_OPTIMUS" == "true" ]] && _OPT_MSG="\n\nGPU Optimus :\n  sudo envycontrol -s hybrid"

dialog --title "✅ Installation terminée !" \
    --msgbox "\
Config  : ${_CONFIG_LABELS[$CONFIG]}\n\
Disque  : $DISK\n\
User    : $USERNAME @ $HOSTNAME\n\
\n\
Prochaines étapes :\n\
  1. Retire la clé USB\n\
  2. Redémarre : reboot${_OPT_MSG}\n\
\n\
📄 Log : /root/ais.log" \
    16 66 >/dev/tty

clear >/dev/tty
echo "📄 Log disponible dans /root/ais.log et /mnt/root/ais.log" >/dev/tty

echo -e "${NC}"