#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║           ARCH LINUX INSTALL — Étape 1 (Live USB)           ║
# ║   Config : UEFI · KDE Plasma · AMD iGPU + NVIDIA 4060       ║
# ║            Optimus Hybride · envycontrol · switcheroo        ║
# ╚══════════════════════════════════════════════════════════════╝
# Usage : bash 1-install.sh
# ⚠️  Ce script va EFFACER ENTIÈREMENT le disque cible !

set -uo pipefail
trap 's=$?; echo -e "\n❌ Erreur ligne $LINENO : $BASH_COMMAND\n"; exit $s' ERR

# ══════════════════════════════════════════════════════════
#  VARIABLES — Modifie ces valeurs avant de lancer !
# ══════════════════════════════════════════════════════════
DISK="/dev/nvme0n1"        # Vérifie avec : fdisk -l
HOSTNAME="mon-laptop"      # Nom de ta machine sur le réseau
USERNAME="tonprenom"       # Nom d'utilisateur (minuscules, sans espace)
TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8"
KEYMAP="fr"

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

# ══════════════════════════════════════════════════════════
#  VÉRIFICATIONS PRÉALABLES
# ══════════════════════════════════════════════════════════
banner "VÉRIFICATIONS"

info "Mode UEFI..."
ls /sys/firmware/efi/efivars &>/dev/null || error "Pas en mode UEFI ! Vérifie les paramètres BIOS."
success "Mode UEFI confirmé"

info "Connexion internet (Ethernet)..."
# Vérifier que l'interface Ethernet est bien up
ETH_IF=$(ip link | awk -F: '/^[0-9]+: e/{print $2; exit}' | tr -d ' ')
if [[ -n "$ETH_IF" ]]; then
    ip link set "$ETH_IF" up 2>/dev/null || true
    # Demander une adresse DHCP si pas encore d'IP
    ip addr show "$ETH_IF" | grep -q "inet " || dhcpcd "$ETH_IF" &>/dev/null || true
fi
ping -c 1 -W 5 archlinux.org &>/dev/null \
    || error "Pas de connexion internet.\n  → Vérifie que le câble Ethernet est bien branché.\n  → Interface détectée : ${ETH_IF:-aucune}\n  → Essaie manuellement : ip link set \$ETH_IF up && dhcpcd \$ETH_IF"
success "Connexion Ethernet OK (interface : ${ETH_IF:-inconnue})"

info "Disque cible : $DISK"
fdisk -l "$DISK" 2>/dev/null | head -5 || error "Disque $DISK introuvable ! Vérifie avec : fdisk -l"
success "Disque trouvé"

# ══════════════════════════════════════════════════════════
#  SAISIE DES MOTS DE PASSE
# ══════════════════════════════════════════════════════════
banner "MOTS DE PASSE"
warn "Les mots de passe ne s'afficheront pas pendant la saisie."

echo -n "→ Mot de passe root : "
read -rs ROOT_PASSWORD; echo
echo -n "→ Confirmer root   : "
read -rs ROOT_CONFIRM; echo
[[ "$ROOT_PASSWORD" == "$ROOT_CONFIRM" ]] || error "Les mots de passe root ne correspondent pas !"
[[ ${#ROOT_PASSWORD} -ge 6 ]]             || error "Mot de passe root trop court (min 6 caractères)"

echo -n "→ Mot de passe pour $USERNAME : "
read -rs USER_PASSWORD; echo
echo -n "→ Confirmer $USERNAME         : "
read -rs USER_CONFIRM; echo
[[ "$USER_PASSWORD" == "$USER_CONFIRM" ]] || error "Les mots de passe utilisateur ne correspondent pas !"
[[ ${#USER_PASSWORD} -ge 6 ]]             || error "Mot de passe utilisateur trop court (min 6 caractères)"

success "Mots de passe validés"

# ══════════════════════════════════════════════════════════
#  CONFIRMATION AVANT DESTRUCTION
# ══════════════════════════════════════════════════════════
banner "CONFIRMATION"
echo -e "${RED}${BOLD}"
echo "  ╔════════════════════════════════════════════╗"
echo "  ║  ⚠️   ATTENTION : DESTRUCTION DE DONNÉES  ║"
echo "  ║                                            ║"
echo "  ║  Le disque suivant va être EFFACÉ :        ║"
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
#  PARTITIONNEMENT (non-interactif avec sgdisk)
# ══════════════════════════════════════════════════════════
banner "PARTITIONNEMENT"
info "Effacement de la table de partitions sur $DISK..."
sgdisk -Z "$DISK" &>/dev/null || true

info "Création des partitions GPT..."
sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
sgdisk -n 2:0:0      -t 2:8300 -c 2:"ROOT" "$DISK"
success "Partitions créées"

# Noms des partitions selon le type de disque (NVMe vs SATA)
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

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
info "Installation des paquets de base (peut prendre plusieurs minutes)..."
pacstrap -K /mnt \
    base base-devel \
    linux linux-headers linux-firmware \
    linux-lts linux-lts-headers \
    amd-ucode \
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

# Note : les variables ${HOSTNAME}, ${USERNAME} etc. sont interpolées MAINTENANT
# Les \$? et \$LINENO sont échappés pour être exécutés DANS le chroot
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

# ── Multilib ─────────────────────────────────────
banner "MULTILIB (32-bit)"
info "Activation du dépôt multilib (nécessaire pour Steam et lib32)..."
sed -i 's/^#\[multilib\]/[multilib]/' /etc/pacman.conf
sed -i '/^\[multilib\]/{n;s/^#Include/Include/}' /etc/pacman.conf
pacman -Sy --noconfirm
success "Multilib activé"

# ── Drivers GPU ──────────────────────────────────
banner "DRIVERS GPU AMD + NVIDIA"
# Forcer resynchronisation complète des bases de données
pacman -Syy --noconfirm
info "Installation des drivers AMD (iGPU)..."
pacman -S --noconfirm \
    mesa vulkan-radeon libva-mesa-driver xf86-video-amdgpu
success "Drivers AMD installés"

info "Installation des drivers NVIDIA propriétaires (4060)..."
pacman -S --noconfirm \
    nvidia nvidia-utils nvidia-settings \
    lib32-nvidia-utils lib32-mesa
success "Drivers NVIDIA installés"

info "Installation des outils Vulkan..."
pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader
success "Vulkan installé"

# ── Config NVIDIA DRM (obligatoire pour Wayland) ─
banner "NVIDIA DRM (WAYLAND)"
info "Activation du mode DRM NVIDIA..."
echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
success "options nvidia_drm écrites"

info "Ajout des modules NVIDIA à l'initramfs..."
sed -i 's/^MODULES=(.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkinitcpio -P
success "initramfs régénéré"

# ── GRUB ─────────────────────────────────────────
banner "GRUB BOOTLOADER"
info "Installation de GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
info "Génération de la configuration GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg
success "GRUB installé et configuré"

# ── KDE Plasma ───────────────────────────────────
banner "KDE PLASMA"
info "Installation de KDE Plasma (peut prendre plusieurs minutes)..."
pacman -S --noconfirm \
    plasma-meta \
    sddm sddm-kcm \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    xdg-user-dirs xdg-desktop-portal xdg-desktop-portal-kde \
    packagekit-qt6 \
    dolphin konsole kate firefox \
    htop fastfetch
success "KDE Plasma installé"

# ── Logiciels supplémentaires (pacman) ───────────
banner "LOGICIELS SUPPLÉMENTAIRES"
info "Multimédia & utilitaires..."
pacman -S --noconfirm \
    vlc \
    okular \
    gnome-disk-utility
success "Multimédia & utilitaires installés"

info "Gaming (Lutris + Steam)..."
pacman -S --noconfirm \
    lutris \
    steam
success "Lutris et Steam installés"

info "XFCE4 — sessions X11 et Wayland (expérimental)..."
# xorg-server  : session X11 pour XFCE4 ET KDE Plasma X11
# labwc        : compositeur Wayland requis pour la session XFCE4 Wayland (EXPÉRIMENTAL)
# Note         : KDE Plasma X11 est automatiquement disponible dans SDDM dès que
#                xorg-server est installé (déjà inclus dans plasma-meta)
pacman -S --noconfirm \
    xfce4 xfce4-goodies \
    xorg-server xorg-xinit \
    labwc
success "XFCE4 installé (X11 stable + Wayland expérimental via labwc)"

# ── switcheroo-control ───────────────────────────
banner "SWITCHEROO-CONTROL"
info "Installation de switcheroo-control (intégration KDE GPU switching)..."
pacman -S --noconfirm switcheroo-control
success "switcheroo-control installé"

# ── Services ─────────────────────────────────────
banner "SERVICES SYSTÈME"
info "Activation des services..."
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable switcheroo-control
success "Services activés : NetworkManager, SDDM, switcheroo-control"

# ── Swapfile ─────────────────────────────────────
banner "SWAPFILE (8 Go)"
info "Création du swapfile de 8 Go (peut prendre un moment)..."
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

# Nettoyage du script temporaire
rm /mnt/chroot-setup.sh

# ══════════════════════════════════════════════════════════
#  FIN
# ══════════════════════════════════════════════════════════
banner "DÉMONTAGE"
info "Démontage des partitions..."
sync
# Tuer les processus résiduels éventuels dans /mnt
fuser -km /mnt 2>/dev/null || true
sleep 1
umount -R /mnt
success "Partitions démontées"

echo -e "\n${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║           ✅ INSTALLATION TERMINÉE !                 ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  1. Retire ta clé USB                               ║"
echo "║  2. Redémarre : reboot                              ║"
echo "║  3. Connecte-toi avec : ${USERNAME}                  ║"
echo "║  4. Lance ensuite : bash 2-post-install.sh          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
