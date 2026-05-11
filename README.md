# 🐧 Scripts d'installation Arch Linux

🇫🇷 **Français** | [🇬🇧 English below](#-arch-linux-install-scripts)

Scripts d'installation Arch Linux automatisés pour quatre configurations — **laptop** (AMD iGPU + NVIDIA), **desktop AMD** (AMD CPU + AMD GPU), **desktop NVIDIA** (AMD CPU + NVIDIA GPU), et **VMware Workstation**.

Chaque configuration comprend deux scripts :
- **Script 1** — lancé depuis la clé USB live, installe et configure le système de base
- **Script 2** — lancé après le premier démarrage dans KDE, installe les paquets AUR et applique le thème

---

## 📋 Prérequis

- ISO Arch Linux démarrée en **mode UEFI**
- **Secure Boot désactivé** dans le BIOS
- Câble Ethernet connecté
- Pour VMware : VM configurée en **mode UEFI** et réseau **NAT**

---

## 📁 Aperçu des scripts

| Script | Cible | Description |
|---|---|---|
| `1-install.sh` | Laptop | AMD iGPU + NVIDIA 4060 · Optimus hybrid · envycontrol |
| `2-post-install.sh` | Laptop | yay · Waterfox · envycontrol · émulateurs · ports · AppImages · Gear Lever · thème KDE |
| `1-install-vm.sh` | VMware Workstation | Drivers VMware SVGA · open-vm-tools |
| `2-post-install-vm.sh` | VMware Workstation | yay · Waterfox · émulateurs · ports · AppImages · Gear Lever · thème KDE |
| `1-install-desktop.sh` | Desktop AMD | AMD CPU + AMD GPU · sans NVIDIA · sans Optimus |
| `2-post-install-desktop.sh` | Desktop AMD | yay · Waterfox · émulateurs · ports · AppImages · Gear Lever · thème KDE |
| `1-install-desktop-nvidia.sh` | Desktop NVIDIA | AMD CPU + NVIDIA GPU · sans iGPU · sans Optimus |
| `2-post-install-desktop-nvidia.sh` | Desktop NVIDIA | yay · Waterfox · émulateurs · ports · AppImages · Gear Lever · thème KDE |

---

## ⚙️ Configuration commune

Tous les scripts 1 partagent ces valeurs par défaut — **à modifier avant de lancer** :

| Variable | Défaut | Description |
|---|---|---|
| `DISK` | `/dev/nvme0n1` | Disque cible — vérifier avec `fdisk -l` |
| `HOSTNAME` | `mon-laptop` / `mon-desktop` / `arch-vm` | Nom de la machine |
| `USERNAME` | `Admin` | Nom d'utilisateur |
| `TIMEZONE` | `Europe/Paris` | Fuseau horaire |
| `LOCALE` | `fr_FR.UTF-8` | Locale système |
| `KEYMAP` | `fr` | Disposition clavier console (AZERTY) |

---

## 🚀 Utilisation

### Laptop (AMD iGPU + NVIDIA 4060)

**Script 1** — depuis la clé USB live :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install.sh -o 1-install.sh && bash 1-install.sh
```

**Script 2** — après le premier démarrage, dans KDE :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install.sh -o 2-post-install.sh && bash 2-post-install.sh
```

---

### VMware Workstation

**Script 1** — depuis la clé USB live dans VMware :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install-vm.sh -o 1-install-vm.sh && bash 1-install-vm.sh
```

**Script 2** — après le premier démarrage, dans KDE :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install-vm.sh -o 2-post-install-vm.sh && bash 2-post-install-vm.sh
```

---

### Desktop (AMD CPU + AMD GPU)

**Script 1** — depuis la clé USB live :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install-desktop.sh -o 1-install-desktop.sh && bash 1-install-desktop.sh
```

**Script 2** — après le premier démarrage, dans KDE :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install-desktop.sh -o 2-post-install-desktop.sh && bash 2-post-install-desktop.sh
```

---

### Desktop (AMD CPU + NVIDIA GPU)

**Script 1** — depuis la clé USB live :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install-desktop-nvidia.sh -o 1-install-desktop-nvidia.sh && bash 1-install-desktop-nvidia.sh
```

**Script 2** — après le premier démarrage, dans KDE :
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install-desktop-nvidia.sh -o 2-post-install-desktop-nvidia.sh && bash 2-post-install-desktop-nvidia.sh
```

---

## 📦 Ce qui est installé

### Système de base (toutes configurations)
- `linux` + `linux-lts` — kernels standard et LTS
- `grub` — bootloader (timeout 1h, boot sur kernel standard par défaut)
- `networkmanager` — gestion réseau
- `amd-ucode` — microcode AMD (laptop et desktop uniquement)

### Environnements de bureau
- **KDE Plasma** (Wayland) — session principale
- **XFCE4** (X11) — session secondaire
- **Cinnamon** (X11) — troisième session
- `sddm` — gestionnaire de connexion

### Applications
| Application | Source |
|---|---|
| Firefox | pacman |
| VLC | pacman |
| Steam | pacman |
| Lutris | pacman |
| Okular | pacman |
| Gnome Disk | pacman |
| Yakuake | pacman |
| Dolphin, Konsole, Kate | pacman |
| wine-staging + gecko + mono + winetricks | pacman |
| Waterfox | Tarball officiel (dernière version via GitHub API) |
| yay | AUR (compilé depuis source) |
| ProtonPlus | AUR — gestionnaire Proton/Wine/DXVK |
| Gear Lever | AUR — gestionnaire AppImages |

### Émulateurs (Script 2)

| Émulateur | Système | Méthode | Emplacement |
|---|---|---|---|
| RetroArch | Frontend multi-systèmes | AppImage (nightly) | `~/Applications/` |
| PCSX2 | PlayStation 2 | AppImage | `~/Applications/` |
| mGBA | Game Boy / GBA | AppImage | `~/Applications/` |
| Cemu | Wii U | AppImage | `~/Applications/` |
| DuckStation | PlayStation 1 | AppImage | `~/Applications/` |
| PPSSPP | PSP | AppImage | `~/Applications/` |
| melonDS | Nintendo DS | AppImage (officielle) | `~/Applications/` |
| Ryujinx Canary | Nintendo Switch | AppImage (Ryubing) | `~/Applications/` |
| Dolphin | GameCube / Wii | Compilé via Docker (Ubuntu 24.04) | `~/.local/share/dolphin-bin/` |
| BGB | Game Boy (Windows) | `.exe` via Wine | `~/.local/share/bgb/` |

### Ports PC — OpenMW & Daggerfall Unity (Script 2)

> ⚠️ Ces ports nécessitent les fichiers du jeu original.

| Port | Jeu | Méthode | Emplacement |
|---|---|---|---|
| OpenMW | Morrowind (TES III) | Tarball GitHub (`OpenMW/openmw`) | `~/.local/share/openmw-bin/` |
| Daggerfall Unity | TES II: Daggerfall | Zip GitHub (`Interkarma/daggerfall-unity`) | `~/.local/share/daggerfall-unity/` |

> **OpenMW** — lance `openmw-launcher` et pointe vers tes fichiers Morrowind.
> **Daggerfall Unity** — les fichiers DOS sont gratuits sur Steam ou via le [guide d'installation](https://github.com/Interkarma/daggerfall-unity/wiki/Installing-Daggerfall-Unity-Cross-Platform).

### Ports PC — HarbourMasters (Script 2)

> ⚠️ Chaque port nécessite une ROM légalement obtenue placée dans `~/Applications/` à côté de l'AppImage.

| Port | Jeu | Méthode | Emplacement |
|---|---|---|---|
| Ship of Harkinian | Zelda: Ocarina of Time | AppImage | `~/Applications/` |
| 2 Ship 2 Harkinian | Zelda: Majora's Mask | AppImage | `~/Applications/` |
| Starship | Star Fox 64 | AppImage | `~/Applications/` |
| SpaghettiKart | Mario Kart 64 | AppImage | `~/Applications/` |
| Ghostship | Super Mario 64 | AppImage (extrait d'un zip) | `~/Applications/` |

### Source Ports (Script 2)

| Port | Jeu | Méthode | Emplacement |
|---|---|---|---|
| vkQuake | Quake 1 (Vulkan) | Compilé depuis source (meson+ninja) | `~/.local/share/vkquake-source/` |
| UZDoom | Moteur Doom (fork ZDoom) | AppImage (officielle GitHub) | `~/Applications/` |
| Yamagi Quake II | Quake II | AppImage (non-officielle) | `~/Applications/` |
| ECWolf | Wolfenstein 3D | Compilé via Docker (Ubuntu 20.04) | `~/.local/share/ecwolf/` |

### Drivers GPU
| Configuration | Drivers |
|---|---|
| Laptop | `mesa` + `vulkan-radeon` (AMD iGPU) · `nvidia` + `nvidia-utils` (NVIDIA) |
| Desktop AMD | `mesa` + `vulkan-radeon` + `lib32-vulkan-radeon` |
| Desktop NVIDIA | `nvidia` + `nvidia-utils` + `lib32-nvidia-utils` · NVIDIA DRM modeset |
| VMware | `mesa` + `xf86-input-vmmouse` |

---

## 🎨 Thème post-installation (Script 2)

Le script 2 détecte automatiquement la session et applique :

**Session KDE :**
- Thème Breeze Sombre via `~/.config/kdeglobals`
- Langue → English US (clavier AZERTY conservé)
- Langue SDDM → English via drop-in systemd
- Fond SDDM → Next Breeze Dark (`5120x2880.png`)
- Boot splash → Plymouth avec thème **sematrix** (effet Matrix)

**Session XFCE :**
- Langue → English US via `~/.xprofile` (clavier AZERTY conservé)

> Se déconnecter et se reconnecter après le script 2 pour appliquer les changements.

---

## 🔧 Gestion du GPU

### Laptop uniquement — Optimus hybrid via `envycontrol` + `switcheroo-control`

| Commande | Effet |
|---|---|
| `envycontrol --query` | Affiche le mode GPU actuel |
| `sudo envycontrol -s hybrid` | AMD par défaut, NVIDIA à la demande |
| `sudo envycontrol -s nvidia` | NVIDIA uniquement (performances max) |
| `sudo envycontrol -s integrated` | AMD uniquement (économie batterie) |

Dans KDE, clic droit sur une app → **"Lancer avec le GPU dédié"**.

Pour Steam : **Propriétés du jeu → Options de lancement** → `prime-run %command%`

### Desktop NVIDIA — un seul GPU, pas de switching

Le driver propriétaire NVIDIA tourne en permanence avec `nvidia_drm modeset=1` pour la compatibilité Wayland.

---

## 🖥️ Sessions disponibles dans SDDM

| Session | Protocole | Statut |
|---|---|---|
| Plasma (Wayland) | Wayland | ✅ Défaut — recommandé |
| Xfce Session | X11 | ✅ Stable |
| Cinnamon | X11 | ✅ Stable |

---

## 🔑 Politique de mot de passe

Le script 1 accepte n'importe quelle longueur de mot de passe. Si le mot de passe fait moins de 6 caractères, un **avertissement de sécurité** s'affiche et une confirmation (`yes/no`) est demandée.

---

## 🛠️ Dépannage

| Problème | Solution |
|---|---|
| Pas d'affichage après install NVIDIA | Vérifier `options nvidia_drm modeset=1` dans `/etc/modprobe.d/nvidia.conf` |
| KDE plante au démarrage | `sudo envycontrol -s integrated`, puis repasser en hybrid |
| Pas de son | `systemctl --user enable --now pipewire pipewire-pulse` |
| Pas de réseau après install | `nmtui` pour configurer la connexion |
| GRUB ne s'affiche pas | Vérifier `GRUB_TIMEOUT=3600` dans `/etc/default/grub`, puis `grub-mkconfig -o /boot/grub/grub.cfg` |
| VMware : résolution bloquée | `systemctl status vmtoolsd` |
| VMware : presse-papiers ne fonctionne pas | `systemctl restart vmtoolsd` |
| VMware : dossiers partagés absents | VM → Paramètres → Options → Dossiers partagés → activer |
| ECWolf ne démarre pas | Installer `sdl2_mixer sdl2_net` · Nécessite les fichiers `.WL6` de Wolfenstein 3D |
| Port HarbourMasters ne démarre pas | Placer la ROM légalement obtenue dans le même dossier que l'AppImage |
| Plymouth casse le boot | Depuis TTY : `bash 2-post-install-vm.sh --remove-plymouth` |

---

## 📄 Licence

MIT — fais-en ce que tu veux.

---
---

# 🐧 Arch Linux Install Scripts

[🇫🇷 Français ci-dessus](#-scripts-dinstallation-arch-linux) | 🇬🇧 **English**

Automated Arch Linux installation scripts for four configurations — **laptop** (AMD iGPU + NVIDIA), **desktop AMD** (AMD CPU + AMD GPU), **desktop NVIDIA** (AMD CPU + NVIDIA GPU), and **VMware Workstation**.

Each configuration comes with two scripts:
- **Script 1** — runs from the live USB, installs and configures the base system
- **Script 2** — runs after the first boot inside KDE, installs AUR packages and applies theming

---

## 📋 Prerequisites

- Arch Linux ISO booted in **UEFI mode**
- **Secure Boot disabled** in BIOS
- Ethernet cable connected
- For VMware: VM set to **UEFI mode** and **NAT network**

---

## 📁 Script Overview

| Script | Target | Description |
|---|---|---|
| `1-install.sh` | Laptop | AMD iGPU + NVIDIA 4060 · Optimus hybrid · envycontrol |
| `2-post-install.sh` | Laptop | yay · Waterfox · envycontrol · emulators · source ports · AppImages · Gear Lever · KDE theming |
| `1-install-vm.sh` | VMware Workstation | VMware SVGA drivers · open-vm-tools |
| `2-post-install-vm.sh` | VMware Workstation | yay · Waterfox · emulators · source ports · AppImages · Gear Lever · KDE theming |
| `1-install-desktop.sh` | Desktop AMD | AMD CPU + AMD GPU · no NVIDIA · no Optimus |
| `2-post-install-desktop.sh` | Desktop AMD | yay · Waterfox · emulators · source ports · AppImages · Gear Lever · KDE theming |
| `1-install-desktop-nvidia.sh` | Desktop NVIDIA | AMD CPU + NVIDIA GPU only · no iGPU · no Optimus |
| `2-post-install-desktop-nvidia.sh` | Desktop NVIDIA | yay · Waterfox · emulators · source ports · AppImages · Gear Lever · KDE theming |

---

## ⚙️ Common Configuration

All Script 1s share these defaults — **edit them before running**:

| Variable | Default | Description |
|---|---|---|
| `DISK` | `/dev/nvme0n1` | Target disk — verify with `fdisk -l` |
| `HOSTNAME` | `mon-laptop` / `mon-desktop` / `arch-vm` | Machine name |
| `USERNAME` | `Admin` | User account name |
| `TIMEZONE` | `Europe/Paris` | System timezone |
| `LOCALE` | `fr_FR.UTF-8` | System locale |
| `KEYMAP` | `fr` | Console keymap (AZERTY) |

---

## 🚀 Usage

### Laptop (AMD iGPU + NVIDIA 4060)

**Script 1** — from the live USB:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install.sh -o 1-install.sh && bash 1-install.sh
```

**Script 2** — after first boot, inside KDE:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install.sh -o 2-post-install.sh && bash 2-post-install.sh
```

---

### VMware Workstation

**Script 1** — from the live USB inside VMware:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install-vm.sh -o 1-install-vm.sh && bash 1-install-vm.sh
```

**Script 2** — after first boot, inside KDE:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install-vm.sh -o 2-post-install-vm.sh && bash 2-post-install-vm.sh
```

---

### Desktop (AMD CPU + AMD GPU)

**Script 1** — from the live USB:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install-desktop.sh -o 1-install-desktop.sh && bash 1-install-desktop.sh
```

**Script 2** — after first boot, inside KDE:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install-desktop.sh -o 2-post-install-desktop.sh && bash 2-post-install-desktop.sh
```

---

### Desktop (AMD CPU + NVIDIA GPU)

**Script 1** — from the live USB:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/1-install-desktop-nvidia.sh -o 1-install-desktop-nvidia.sh && bash 1-install-desktop-nvidia.sh
```

**Script 2** — after first boot, inside KDE:
```bash
curl -fsSL https://raw.githubusercontent.com/Deadfalt999/arch-install-script/main/2-post-install-desktop-nvidia.sh -o 2-post-install-desktop-nvidia.sh && bash 2-post-install-desktop-nvidia.sh
```

---

## 📦 What Gets Installed

### Base system (all configurations)
- `linux` + `linux-lts` — standard and LTS kernels
- `grub` — bootloader (1h timeout, boots standard kernel by default)
- `networkmanager` — network management
- `amd-ucode` — AMD microcode (laptop and desktop only)

### Desktop environments
- **KDE Plasma** (Wayland) — primary session
- **XFCE4** (X11) — secondary session
- **Cinnamon** (X11) — third session
- `sddm` — display manager

### Applications
| App | Source |
|---|---|
| Firefox | pacman |
| VLC | pacman |
| Steam | pacman |
| Lutris | pacman |
| Okular | pacman |
| Gnome Disk | pacman |
| Yakuake | pacman |
| Dolphin, Konsole, Kate | pacman |
| wine-staging + gecko + mono + winetricks | pacman |
| Waterfox | Official tarball (auto-latest via GitHub API) |
| yay | AUR (compiled from source) |
| ProtonPlus | AUR — Proton/Wine/DXVK manager |
| Gear Lever | AUR — AppImage manager |

### Emulators (Script 2)

| Emulator | System | Method | Location |
|---|---|---|---|
| RetroArch | Multi-system frontend | AppImage (nightly) | `~/Applications/` |
| PCSX2 | PlayStation 2 | AppImage | `~/Applications/` |
| mGBA | Game Boy / GBA | AppImage | `~/Applications/` |
| Cemu | Wii U | AppImage | `~/Applications/` |
| DuckStation | PlayStation 1 | AppImage | `~/Applications/` |
| PPSSPP | PSP | AppImage | `~/Applications/` |
| melonDS | Nintendo DS | AppImage (official) | `~/Applications/` |
| Ryujinx Canary | Nintendo Switch | AppImage (Ryubing) | `~/Applications/` |
| Dolphin | GameCube / Wii | Compiled via Docker (Ubuntu 24.04) | `~/.local/share/dolphin-bin/` |
| BGB | Game Boy (Windows) | `.exe` via Wine | `~/.local/share/bgb/` |

### PC Ports — OpenMW & Daggerfall Unity (Script 2)

> ⚠️ These ports require the original game files.

| Port | Game | Method | Location |
|---|---|---|---|
| OpenMW | Morrowind (TES III) | tarball GitHub (`OpenMW/openmw`) | `~/.local/share/openmw-bin/` |
| Daggerfall Unity | TES II: Daggerfall | zip GitHub (`Interkarma/daggerfall-unity`) | `~/.local/share/daggerfall-unity/` |

> **OpenMW** — run `openmw-launcher` and point to your Morrowind files.
> **Daggerfall Unity** — DOS game files are free on Steam or via the [cross-platform install guide](https://github.com/Interkarma/daggerfall-unity/wiki/Installing-Daggerfall-Unity-Cross-Platform).

### PC Ports — HarbourMasters (Script 2)

> ⚠️ Each port requires a legally obtained ROM placed in `~/Applications/` alongside the AppImage.

| Port | Game | Method | Location |
|---|---|---|---|
| Ship of Harkinian | Zelda: Ocarina of Time | AppImage | `~/Applications/` |
| 2 Ship 2 Harkinian | Zelda: Majora's Mask | AppImage | `~/Applications/` |
| Starship | Star Fox 64 | AppImage | `~/Applications/` |
| SpaghettiKart | Mario Kart 64 | AppImage | `~/Applications/` |
| Ghostship | Super Mario 64 | AppImage (extracted from zip) | `~/Applications/` |

### Source Ports (Script 2)

| Port | Game | Method | Location |
|---|---|---|---|
| vkQuake | Quake 1 (Vulkan) | Compiled from source (meson+ninja) | `~/.local/share/vkquake-source/` |
| UZDoom | Doom engine (ZDoom fork) | AppImage (official GitHub) | `~/Applications/` |
| Yamagi Quake II | Quake II | AppImage (unofficial) | `~/Applications/` |
| ECWolf | Wolfenstein 3D | Compiled via Docker (Ubuntu 20.04) | `~/.local/share/ecwolf/` |

### GPU drivers
| Configuration | Drivers |
|---|---|
| Laptop | `mesa` + `vulkan-radeon` (AMD iGPU) · `nvidia` + `nvidia-utils` (NVIDIA) |
| Desktop AMD | `mesa` + `vulkan-radeon` + `lib32-vulkan-radeon` |
| Desktop NVIDIA | `nvidia` + `nvidia-utils` + `lib32-nvidia-utils` · NVIDIA DRM modeset |
| VMware | `mesa` + `xf86-input-vmmouse` |

---

## 🎨 Post-install Theming (Script 2)

Script 2 auto-detects the current session and applies:

**KDE session:**
- Breeze Dark theme via `~/.config/kdeglobals`
- Language → English US (keyboard stays French AZERTY)
- SDDM language → English via systemd drop-in
- SDDM wallpaper → Next Breeze Dark (`5120x2880.png`)
- Boot splash → Plymouth with **sematrix** theme (Matrix effect)

**XFCE session:**
- Language → English US via `~/.xprofile` (keyboard stays French AZERTY)

> Log out and back in after running Script 2 for changes to take effect.

---

## 🔧 GPU Management

### Laptop only — Optimus hybrid via `envycontrol` + `switcheroo-control`

| Command | Effect |
|---|---|
| `envycontrol --query` | Show current GPU mode |
| `sudo envycontrol -s hybrid` | AMD by default, NVIDIA on demand |
| `sudo envycontrol -s nvidia` | NVIDIA only (max performance) |
| `sudo envycontrol -s integrated` | AMD only (max battery) |

In KDE, right-click any app → **"Launch using dedicated GPU"** to run it on the NVIDIA.

For Steam: **Game properties → Launch options** → `prime-run %command%`

### Desktop NVIDIA — single GPU, no switching needed

The NVIDIA proprietary driver runs at all times with `nvidia_drm modeset=1` enabled for Wayland compatibility.

---

## 🖥️ Available Sessions in SDDM

| Session | Protocol | Status |
|---|---|---|
| Plasma (Wayland) | Wayland | ✅ Default — recommended |
| Xfce Session | X11 | ✅ Stable |
| Cinnamon | X11 | ✅ Stable |

---

## 🔑 Password Policy

Script 1 accepts any password length. If the password is under 6 characters, a **security warning** is displayed and confirmation (`yes/no`) is required before continuing.

---

## 🛠️ Troubleshooting

| Problem | Solution |
|---|---|
| No display after NVIDIA install | Check `options nvidia_drm modeset=1` in `/etc/modprobe.d/nvidia.conf` |
| KDE crashes on boot | Run `sudo envycontrol -s integrated`, then switch back to hybrid |
| No sound | `systemctl --user enable --now pipewire pipewire-pulse` |
| No network after install | `nmtui` to configure the connection |
| GRUB not showing | Check `GRUB_TIMEOUT=3600` in `/etc/default/grub`, then `grub-mkconfig -o /boot/grub/grub.cfg` |
| VMware: resolution locked | Check `systemctl status vmtoolsd` |
| VMware: clipboard not working | `systemctl restart vmtoolsd` |
| VMware: shared folders missing | VM → Settings → Options → Shared Folders → enable |
| ECWolf won't start | Install `sdl2_mixer sdl2_net` · Requires Wolfenstein 3D `.WL6` game files |
| HarbourMasters port won't launch | Place legally obtained ROM in the same folder as the AppImage |
| Plymouth breaks boot | From TTY: `bash 2-post-install-vm.sh --remove-plymouth` |

---

## 📄 License

MIT — do whatever you want with it.
