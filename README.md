# 🐧 Arch Linux Install Scripts

Automated Arch Linux installation scripts for three different configurations — **laptop** (AMD iGPU + NVIDIA), **desktop** (AMD CPU + AMD GPU), **desktop NVIDIA** (AMD CPU + NVIDIA GPU), and **VMware Workstation**.

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
| Dolphin | GameCube / Wii | Compiled from source | `~/.local/share/dolphin-source/` |
| BGB | Game Boy (Windows) | `.exe` via Wine | `~/.local/share/bgb/` |

### PC Ports — OpenMW & Daggerfall Unity (Script 2)

> ⚠️ These ports require the original game files.

| Port | Game | Method | Location |
|---|---|---|---|
| OpenMW | Morrowind (TES III) | tarball GitHub (`OpenMW/openmw`) | `~/.local/share/openmw-bin/` |
| Daggerfall Unity | TES II: Daggerfall | zip GitHub (`Interkarma/daggerfall-unity`) | `~/.local/share/daggerfall-unity/` |

> **OpenMW** — run `openmw-launcher` and point to your Morrowind files.
> **Daggerfall Unity** — DOS game files are free on Steam or via the [cross-platform install guide](https://github.com/Interkarma/daggerfall-unity/wiki/Installing-Daggerfall-Unity-Cross-Platform). The Google Drive game data link is not automated — manual download required.

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
- SDDM language → English via systemd drop-in (`/etc/systemd/system/sddm.service.d/`)
- SDDM wallpaper → Next Breeze Dark (`5120x2880.png`)

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

The NVIDIA proprietary driver runs at all times with `nvidia_drm modeset=1` enabled for Wayland compatibility. No additional configuration required.

---

## 🖥️ Available Sessions in SDDM

| Session | Protocol | Status |
|---|---|---|
| Plasma (Wayland) | Wayland | ✅ Default — recommended |
| Xfce Session | X11 | ✅ Stable |
| Cinnamon | X11 | ✅ Stable |

---

## 🔑 Password Policy

Script 1 accepts any password length. If the password is under 6 characters, a **security warning** is displayed explaining the risks, and confirmation (`yes/no`) is required before continuing.

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
| ECWolf won't compile | Docker method uses Ubuntu 20.04 (GCC 9) to avoid the tmemory.h const bug |
| HarbourMasters port won't launch | Place your legally obtained ROM in the same folder as the AppImage |

---

## 📄 License

MIT — do whatever you want with it.
