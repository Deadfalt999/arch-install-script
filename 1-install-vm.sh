#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║        ARCH LINUX INSTALL — VMware Workstation               ║
# ║        Config : UEFI · KDE Plasma · open-vm-tools           ║
# ║        Alternative à 1-install.sh (laptop AMD+NVIDIA)       ║
# ╚══════════════════════════════════════════════════════════════╝
# Usage : bash 1-install-vm.sh
# ⚠️  Ce script va EFFACER ENTIÈREMENT le disque virtuel cible !

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

# Fonction ask — accepte o/oui/y/yes/1 et n/non/no/0
ask() {
    local prompt="$1"
    local default="${2:-o}"
    local answer
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

# ══════════════════════════════════════════════════════════
#  WIZARD DE CONFIGURATION
# ══════════════════════════════════════════════════════════
banner "CONFIGURATION"
echo -e "${BOLD}Réponds aux questions suivantes. Appuie sur Entrée pour garder la valeur par défaut.${NC}\n"

# Disque — détection automatique selon le type VMware
echo -e "${BLUE}Disques disponibles :${NC}"
fdisk -l 2>/dev/null | grep "^Disk /dev" | grep -v "loop"
echo ""
echo -e "${YELLOW}Types de disques VMware supportés :${NC}"
echo -e "  SCSI (défaut) → ${GREEN}/dev/sda${NC}"
echo -e "  SATA          → ${GREEN}/dev/sda${NC}"
echo -e "  IDE           → ${GREEN}/dev/sda${NC}"
echo -e "  NVMe          → ${GREEN}/dev/nvme0n1${NC}"
echo ""

# Détection automatique du premier disque disponible
_AUTO_DISK=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | grep "disk" | head -1 | awk '{print "/dev/"$1}')
_AUTO_DISK="${_AUTO_DISK:-/dev/sda}"

read -rp "$(echo -e "${YELLOW}Disque cible${NC} [$_AUTO_DISK]: ")" _DISK || true
DISK="${_DISK:-$_AUTO_DISK}"

# Adapter les noms de partitions selon le type de disque
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

# Hostname
read -rp "$(echo -e "${YELLOW}Nom de la machine (hostname)${NC} [arch-vm]: ")" _HOSTNAME || true
HOSTNAME="${_HOSTNAME:-arch-vm}"

# Username
read -rp "$(echo -e "${YELLOW}Nom d'utilisateur${NC} [Admin]: ")" _USERNAME || true
USERNAME="${_USERNAME:-Admin}"

# Timezone
read -rp "$(echo -e "${YELLOW}Fuseau horaire${NC} [Europe/Paris]: ")" _TIMEZONE || true
TIMEZONE="${_TIMEZONE:-Europe/Paris}"

# Locale
read -rp "$(echo -e "${YELLOW}Locale${NC} [fr_FR.UTF-8]: ")" _LOCALE || true
LOCALE="${_LOCALE:-fr_FR.UTF-8}"

# Keymap
read -rp "$(echo -e "${YELLOW}Clavier console${NC} [fr]: ")" _KEYMAP || true
KEYMAP="${_KEYMAP:-fr}"

echo ""
echo -e "${BOLD}Configuration retenue :${NC}"
echo -e "  Disque   : ${GREEN}$DISK${NC}"
echo -e "  Hostname : ${GREEN}$HOSTNAME${NC}"
echo -e "  User     : ${GREEN}$USERNAME${NC}"
echo -e "  Timezone : ${GREEN}$TIMEZONE${NC}"
echo -e "  Locale   : ${GREEN}$LOCALE${NC}"
echo -e "  Clavier  : ${GREEN}$KEYMAP${NC}"
echo ""

# ══════════════════════════════════════════════════════════
#  VÉRIFICATIONS PRÉALABLES
# ══════════════════════════════════════════════════════════
banner "VÉRIFICATIONS"

info "Mode UEFI..."
ls /sys/firmware/efi/efivars &>/dev/null || error "Pas en mode UEFI ! Active l'UEFI dans les paramètres de la VM."
success "Mode UEFI confirmé"

info "Connexion internet (NAT VMware)..."
ping -c 1 -W 5 archlinux.org &>/dev/null \
    || error "Pas de connexion internet.\n  → Vérifie que la VM est en mode NAT dans VMware\n  → Network Adapter → NAT"
success "Connexion internet OK"

info "Disque virtuel cible : $DISK"
fdisk -l "$DISK" 2>/dev/null | head -5 || error "Disque $DISK introuvable ! Vérifie avec : fdisk -l"
success "Disque trouvé"

# ══════════════════════════════════════════════════════════
#  SAISIE DES MOTS DE PASSE
# ══════════════════════════════════════════════════════════
banner "MOTS DE PASSE"
warn "Les mots de passe ne s'afficheront pas pendant la saisie."

warn_weak_password() {
    local label="$1"
    local pwd="$2"
    if [[ ${#pwd} -lt 6 ]]; then
        echo -e "\n${RED}${BOLD}⚠️  AVERTISSEMENT DE SÉCURITÉ — Mot de passe $label${NC}"
        echo -e "${YELLOW}  Moins de 6 caractères — extrêmement vulnérable.${NC}"
        ask "  Continuer quand même ?" "n" || error "Installation annulée — choisis un mot de passe plus fort."
    fi
}

echo -n "→ Mot de passe root : "
read -rs ROOT_PASSWORD; echo
echo -n "→ Confirmer root   : "
read -rs ROOT_CONFIRM; echo
[[ "$ROOT_PASSWORD" == "$ROOT_CONFIRM" ]] || error "Les mots de passe root ne correspondent pas !"
warn_weak_password "root" "$ROOT_PASSWORD"

echo -n "→ Mot de passe pour $USERNAME : "
read -rs USER_PASSWORD; echo
echo -n "→ Confirmer $USERNAME         : "
read -rs USER_CONFIRM; echo
[[ "$USER_PASSWORD" == "$USER_CONFIRM" ]] || error "Les mots de passe utilisateur ne correspondent pas !"
warn_weak_password "$USERNAME" "$USER_PASSWORD"

success "Mots de passe validés"

# ══════════════════════════════════════════════════════════
#  CONFIRMATION AVANT DESTRUCTION
# ══════════════════════════════════════════════════════════
banner "CONFIRMATION"
echo -e "${RED}${BOLD}"
echo "  ╔════════════════════════════════════════════╗"
echo "  ║  ⚠️   ATTENTION : DESTRUCTION DE DONNÉES  ║"
echo "  ║                                            ║"
echo "  ║  Le disque virtuel suivant va être EFFACÉ :║"
echo "  ║  $DISK                                     ║"
echo "  ╚════════════════════════════════════════════╝"
echo -e "${NC}"

fdisk -l "$DISK" | grep -E "^Disk|^/dev"
echo ""
echo -n "  Tape 'oui' pour confirmer et démarrer l'installation : "
read CONFIRM
[[ "$CONFIRM" == "oui" ]] || error "Installation annulée."

# ══════════════════════════════════════════════════════════
#  HORLOGE
# ══════════════════════════════════════════════════════════
banner "HORLOGE"
info "Synchronisation NTP..."
timedatectl set-ntp true
success "Horloge synchronisée"

# ══════════════════════════════════════════════════════════
#  PARTITIONNEMENT
# ══════════════════════════════════════════════════════════
banner "PARTITIONNEMENT"
info "Effacement de la table de partitions sur $DISK..."
sgdisk -Z "$DISK" &>/dev/null || true

info "Création des partitions GPT..."
sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
sgdisk -n 2:0:0      -t 2:8300 -c 2:"ROOT" "$DISK"
success "Partitions créées (EFI=$EFI_PART ROOT=$ROOT_PART)"

info "Vérification..."
fdisk -l "$DISK"

# ══════════════════════════════════════════════════════════
#  FORMATAGE
# ══════════════════════════════════════════════════════════
banner "FORMATAGE"
info "Formatage EFI en FAT32 : $EFI_PART"
mkfs.fat -F32 "$EFI_PART"

info "Formatage root en ext4 : $ROOT_PART"
mkfs.ext4 -F "$ROOT_PART"
success "Partitions formatées"

# ══════════════════════════════════════════════════════════
#  MONTAGE
# ══════════════════════════════════════════════════════════
banner "MONTAGE"
info "Montage des partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
success "Partitions montées"

# ══════════════════════════════════════════════════════════
#  MIROIRS (France)
# ══════════════════════════════════════════════════════════
banner "MIROIRS"
info "Sélection des miroirs les plus rapides (France)..."
reflector --country France --age 12 --protocol https --sort rate \
    --save /etc/pacman.d/mirrorlist
success "Miroirs configurés"

# ══════════════════════════════════════════════════════════
#  INSTALLATION BASE
# ══════════════════════════════════════════════════════════
banner "SYSTÈME DE BASE"
info "Installation des paquets de base..."
# Pas de amd-ucode dans une VM (microcode inutile)
pacstrap -K /mnt \
    base base-devel \
    linux linux-headers linux-firmware \
    linux-lts linux-lts-headers \
    networkmanager \
    vim nano \
    git wget curl \
    grub efibootmgr \
    sudo \
    gptfdisk
success "Système de base installé"

# ══════════════════════════════════════════════════════════
#  FSTAB
# ══════════════════════════════════════════════════════════
banner "FSTAB"
info "Génération du fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
success "fstab généré :"
cat /mnt/etc/fstab

# ══════════════════════════════════════════════════════════
#  GÉNÉRATION DU SCRIPT CHROOT
# ══════════════════════════════════════════════════════════
banner "PRÉPARATION CHROOT"
info "Génération du script de configuration chroot..."

cat > /mnt/chroot-setup.sh << HEREDOC
#!/bin/bash
set -uo pipefail
trap 's=\$?; echo -e "\n❌ Erreur chroot ligne \$LINENO : \$BASH_COMMAND\n"; exit \$s' ERR

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "\n\${BLUE}[CHROOT]\${NC} \$1"; }
success() { echo -e "\${GREEN}[OK]\${NC} \$1"; }
banner()  { echo -e "\n\${BOLD}══ \$1 ══\${NC}"; }

# ── Timezone ────────────────────────────────────
banner "TIMEZONE"
info "Configuration de ${TIMEZONE}..."
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
success "Timezone configurée"

# ── Locale ──────────────────────────────────────
banner "LOCALE"
info "Génération des locales..."
sed -i 's/^#fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
success "Locale configurée : ${LOCALE}"

# ── Hostname ─────────────────────────────────────
banner "HOSTNAME"
info "Configuration du hostname : ${HOSTNAME}"
echo "${HOSTNAME}" > /etc/hostname
cat >> /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
success "Hostname configuré"

# ── Utilisateurs ─────────────────────────────────
banner "UTILISATEURS"
info "Mot de passe root..."
echo "root:${ROOT_PASSWORD}" | chpasswd
success "Mot de passe root défini"

info "Création de l'utilisateur ${USERNAME}..."
useradd -m -G wheel,video,audio -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
success "Utilisateur ${USERNAME} créé"

info "Activation de sudo pour le groupe wheel..."
sed -i 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
success "Sudo configuré"

# ── Clavier (SDDM + KDE + XFCE) ──────────────────
banner "CONFIGURATION CLAVIER"

info "Clavier français pour SDDM (écran de connexion)..."
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/keyboard.conf << EOF
[General]
InputMethod=
EOF
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "fr"
    Option "XkbModel" "pc105"
EndSection
EOF
success "Clavier SDDM configuré (fr)"

info "Clavier français pour KDE Plasma (Wayland)..."
mkdir -p /home/${USERNAME}/.config
cat > /home/${USERNAME}/.config/kxkbrc << EOF
[Layout]
DisplayNames=
LayoutList=fr
Model=pc105
VariantList=
EOF
success "Clavier KDE configuré (fr)"

info "Clavier français pour XFCE4 (X11)..."
mkdir -p /home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml
cat > /home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="keyboard-layout" version="1.0">
  <property name="Default" type="empty">
    <property name="XkbDisable" type="bool" value="false"/>
    <property name="XkbLayout" type="string" value="fr"/>
    <property name="XkbModel" type="string" value="pc105"/>
    <property name="XkbVariant" type="string" value=""/>
  </property>
</channel>
EOF
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
success "Clavier XFCE configuré (fr azerty)"

# ── Multilib ─────────────────────────────────────
banner "MULTILIB (32-bit)"
info "Activation du dépôt multilib..."
sed -i 's/^#\[multilib\]/[multilib]/' /etc/pacman.conf
sed -i '/^\[multilib\]/{n;s/^#Include/Include/}' /etc/pacman.conf
pacman -Syy --noconfirm
success "Multilib activé"

# ── Drivers GPU VMware ───────────────────────────
banner "DRIVERS GPU VMWARE"
info "Installation des drivers graphiques VMware..."
# xf86-video-vmware supprimé des dépôts Arch — le module kernel vmwgfx gère l'affichage
# xf86-input-vmmouse : driver souris VMware
# mesa               : rendu OpenGL
# xorg-server        : serveur X11 (requis pour KDE X11 et XFCE)
pacman -S --noconfirm \
    mesa \
    xf86-input-vmmouse \
    xorg-server xorg-xinit \
    vulkan-icd-loader
success "Drivers VMware installés"

# ── open-vm-tools ────────────────────────────────
banner "OPEN-VM-TOOLS"
info "Installation de open-vm-tools (intégration VMware)..."
# Fournit : clipboard bidirectionnel, dossiers partagés,
#           résolution automatique, drag & drop
pacman -S --noconfirm \
    open-vm-tools \
    gtkmm3
success "open-vm-tools installé"

# ── GRUB ─────────────────────────────────────────
banner "GRUB BOOTLOADER"
info "Installation de GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
info "Configuration de GRUB (pas de timer, boot sur kernel standard)..."
# Pas de timer — démarre immédiatement sans afficher le menu
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3600/' /etc/default/grub
# Le kernel standard (non-LTS) est la première entrée générée par grub-mkconfig
sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
sed -i 's/^#?GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080x32/' /etc/default/grub
info "Génération de la configuration GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg
success "GRUB installé et configuré (timeout=0, default=kernel standard)"

# ── KDE Plasma ───────────────────────────────────
banner "KDE PLASMA"
info "Installation de KDE Plasma..."
pacman -S --noconfirm \
    plasma-meta \
    sddm sddm-kcm \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    xdg-user-dirs xdg-desktop-portal xdg-desktop-portal-kde \
    packagekit-qt6 \
    dolphin konsole kate firefox \
    htop fastfetch
success "KDE Plasma installé"

# ── Logiciels supplémentaires ────────────────────
banner "LOGICIELS SUPPLÉMENTAIRES"
info "Multimédia & utilitaires..."
pacman -S --noconfirm \
    vlc \
    okular \
    gnome-disk-utility \
    yakuake
success "Multimédia & utilitaires installés"

info "Gaming (Lutris + Steam)..."
pacman -S --noconfirm \
    lutris \
    steam
success "Lutris et Steam installés"

info "XFCE4 — session X11..."
# labwc retiré : XFCE4 Wayland expérimental supprimé, X11 uniquement
# Plasma reste en Wayland, XFCE4 en X11
pacman -S --noconfirm \
    xfce4 xfce4-goodies
success "XFCE4 installé (X11)"

info "Installation de Cinnamon (X11)..."
pacman -S --noconfirm \
    cinnamon
success "Cinnamon installé (X11)"

# ── Services ─────────────────────────────────────
banner "SERVICES SYSTÈME"
info "Activation des services..."
systemctl enable NetworkManager
systemctl enable sddm
# Services open-vm-tools (intégration VMware)
systemctl enable vmtoolsd
systemctl enable vmware-vmblock-fuse
success "Services activés : NetworkManager, SDDM, vmtoolsd, vmware-vmblock-fuse"

# ── Swapfile ─────────────────────────────────────
banner "SWAPFILE (8 Go)"
info "Création du swapfile de 8 Go..."
dd if=/dev/zero of=/swapfile bs=1M count=8192 status=progress
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap defaults 0 0' >> /etc/fstab
success "Swapfile créé et ajouté au fstab"

echo -e "\n\${GREEN}\${BOLD}✅ Configuration chroot terminée avec succès !\${NC}\n"
HEREDOC

chmod +x /mnt/chroot-setup.sh
success "Script chroot généré"

# ══════════════════════════════════════════════════════════
#  EXÉCUTION DANS LE CHROOT
# ══════════════════════════════════════════════════════════
banner "CONFIGURATION (CHROOT)"
info "Lancement de la configuration système dans le chroot..."
arch-chroot /mnt /chroot-setup.sh

rm /mnt/chroot-setup.sh

# ══════════════════════════════════════════════════════════
#  FIN
# ══════════════════════════════════════════════════════════
banner "DÉMONTAGE"
info "Démontage des partitions..."
sync
umount -R -l /mnt
success "Partitions démontées"

echo -e "\n${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        ✅ INSTALLATION VM TERMINÉE !                     ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  1. Éjecte l'ISO dans VMware (VM → Removable Devices)   ║"
echo "║  2. Redémarre : reboot                                  ║"
echo "║  3. Connecte-toi avec : ${USERNAME}                      ║"
echo "║  4. Lance ensuite : bash 2-post-install-vm.sh           ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  ⚠️  NE PAS lancer 2-post-install.sh (version laptop)   ║"
echo "║     → envycontrol et NVIDIA ne fonctionnent pas en VM   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
