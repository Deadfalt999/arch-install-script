# 🐧 Arch Linux Install Scripts

Automated Arch Linux installation scripts for three different configurations — **laptop** (AMD iGPU + NVIDIA), **desktop** (AMD CPU + AMD GPU), and **VMware Workstation**.

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
| `2-post-install.sh` | Laptop | yay · Waterfox · envycontrol · emulators · AppImages · Gear Lever · KDE theming |
| `1-install-vm.sh` | VMware Workstation | VMware SVGA drivers · open-vm-tools |
| `2-post-install-vm.sh` | VMware Workstation | yay · Waterfox · emulators · AppImages · Gear Lever · KDE theming |
| `1-install-desktop.sh` | Desktop AMD | AMD CPU + AMD GPU · no NVIDIA · no Optimus |
| `2-post-install-desktop.sh` | Desktop AMD | yay · Waterfox · emulators · AppImages · Gear Lever · KDE theming |
| `1-install-desktop-nvidia.sh` | Desktop NVIDIA | AMD CPU + NVIDIA GPU only · no iGPU · no Optimus |
| `2-post-install-desktop-nvidia.sh` | Desktop NVIDIA | yay · Waterfox · emulators · AppImages · Gear Lever · KDE theming |

---

## ⚙️ Common Configuration

All three Script 1s share these defaults — **edit them before running**:

| Variable | Default | Description |
|---|---|---|
| `DISK` | `/dev/nvme0n1` | Target disk — verify with `fdisk -l` |
| `HOSTNAME` | `mon-laptop` / `mon-desktop` / `arch-vm` | Machine name |
| `USERNAME` | `Admin` | User account name |
| `TIMEZONE` | `Europe/Paris` | System timezone |
| `LOCALE` | `fr_FR.UTF-8` | System locale |
| `KEYMAP` | `fr` | Console keymap |

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

### Desktop environment
- **KDE Plasma** (Wayland) — primary session
- **XFCE4** (X11) — secondary session
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
| Waterfox | Official tarball (auto-latest) |
| yay | AUR (compiled from source) |
| ProtonPlus | AUR |
| Gear Lever | AUR — AppImage manager |

### Emulators (Script 2)

| Emulator | System | Method | Location |
|---|---|---|---|
| RetroArch | Multi-system frontend | AppImage (nightly) | `~/Applications/` |
| PCSX2 | PlayStation 2 | AppImage (latest) | `~/Applications/` |
| mGBA | Game Boy / GBA | AppImage (latest) | `~/Applications/` |
| Cemu | Wii U | AppImage (latest) | `~/Applications/` |
| DuckStation | PlayStation 1 | AppImage (latest) | `~/Applications/` |
| Dolphin | GameCube / Wii | pacman | system |
| PPSSPP | PSP | pacman | system |
| DeSmuME | Nintendo DS | pacman | system |
| Ryujinx Canary | Nintendo Switch | AUR (ryujinx-canary) | system |
| BGB | Game Boy (Windows) | `.exe` via Wine | `~/.local/share/bgb/` |

> AppImages are downloaded automatically from their official GitHub releases and stored in `~/Applications/`. Gear Lever integrates them into the app menu — just drag and drop any AppImage onto it.

### GPU drivers
| Configuration | Drivers |
|---|---|
| Laptop | `mesa` + `vulkan-radeon` (AMD iGPU) · `nvidia` + `nvidia-utils` (NVIDIA) |
| Desktop AMD | `mesa` + `vulkan-radeon` + `lib32-vulkan-radeon` |
| Desktop NVIDIA | `nvidia` + `nvidia-utils` + `lib32-nvidia-utils` · NVIDIA DRM modeset |
| VMware | `mesa` + `xf86-input-vmmouse` |

---

## 🎨 Post-install Theming (Script 2)

Script 2 detects the current session automatically and applies:

**KDE session:**
- Breeze Dark theme (`kdeglobals`)
- Language set to English US (keyboard stays French AZERTY)
- SDDM language set to English via systemd drop-in
- SDDM wallpaper set to Next Breeze Dark

**XFCE session:**
- Language set to English US via `~/.xprofile` (keyboard stays French AZERTY)

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

| Session | Protocol | Config |
|---|---|---|
| Plasma (Wayland) | Wayland | ✅ Default — recommended |
| Xfce Session | X11 | ✅ Stable |

---

## 🔑 Password Policy

Script 1 accepts any password length. If the password is under 6 characters, a **security warning** is displayed and confirmation is required before continuing.

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

---

## 📄 License

MIT — do whatever you want with it.
