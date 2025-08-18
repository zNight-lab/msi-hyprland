#!/bin/bash
set -euo pipefail

echo "=== MSI Katana 15 B13VGK Full Auto Arch + JaKooLit Hyprland Installer ==="
echo

# --- 1. Select disk ---
echo "Available disks:"
lsblk -dno NAME,SIZE,MODEL | awk '{print "/dev/" $1 "\t" $2 "\t" $3}'

read -rp "Enter disk device to install Arch on (e.g. /dev/nvme0n1): " DISK

if [ ! -b "$DISK" ]; then
  echo "Error: Device $DISK does not exist."
  exit 1
fi

read -rp "WARNING: ALL DATA ON $DISK WILL BE LOST! Type 'YES' to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborting."
  exit 1
fi

# --- 2. User info ---
read -rp "Enter your desired username: " USERNAME
USERNAME=${USERNAME:-znight}

read -rp "Enter hostname for this system: " HOSTNAME
HOSTNAME=${HOSTNAME:-katana15}

read -rp "Enter your timezone (default America/New_York): " TIMEZONE
TIMEZONE=${TIMEZONE:-America/New_York}

# --- 3. Disk partitioning ---
echo "Partitioning $DISK..."

sgdisk --zap-all "$DISK"

sgdisk -n1:0:+512M -t1:ef00 -c1:"EFI System Partition" "$DISK"
sgdisk -n2:0:0 -t2:8300 -c2:"Linux root partition" "$DISK"

# Format partitions
PART_EFI="${DISK}1"
PART_ROOT="${DISK}2"

echo "Formatting partitions..."
mkfs.fat -F32 "$PART_EFI"
mkfs.ext4 "$PART_ROOT"

# --- 4. Mount and prepare base install ---
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot

# --- 5. Install base system ---
echo "Installing base system..."
pacstrap /mnt base base-devel linux linux-headers linux-firmware vim nano sudo networkmanager

# --- 6. Fstab generation ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- 7. Chroot setup ---
echo "Entering chroot to configure system..."

arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOL

# Create user
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME
chmod 440 /etc/sudoers.d/$USERNAME

# Set root password (empty)
echo "root::0:0:root:/root:/bin/bash" | chpasswd -e || true

# Enable NetworkManager
systemctl enable NetworkManager

# Install bootloader (systemd-boot)
bootctl install

cat > /boot/loader/loader.conf <<EOL
default arch
timeout 3
console-mode max
editor no
EOL

cat > /boot/loader/entries/arch.conf <<EOL
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=$(blkid -s UUID -o value $PART_ROOT) rw nvidia-drm.modeset=1
EOL

# Enable multilib repo and update system
sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
pacman -Sy --noconfirm

# Install NVIDIA, kernel headers, gaming, VM tools
pacman -S --noconfirm nvidia-dkms nvidia-utils nvidia-settings linux-headers base-devel git \
pipewire pipewire-pulse wireplumber alsa-utils pavucontrol NetworkManager qemu libvirt edk2-ovmf dnsmasq bridge-utils virt-manager steam heroiclient lutris gamemode mangohud lib32-nvidia-utils lib32-vulkan-icd-loader vulkan-icd-loader vulkan-tools vulkan-validation-layers lib32-vulkan-tools tlp powertop htop neofetch

systemctl enable libvirtd tlp NetworkManager

# Install yay AUR helper as user
su - $USERNAME -c "
git clone https://aur.archlinux.org/yay.git /home/$USERNAME/yay
cd /home/$USERNAME/yay
makepkg -si --noconfirm
"

# Install Looking Glass client from AUR
su - $USERNAME -c "yay -S --noconfirm looking-glass-git"

# Setup Hyprland config (basic NVIDIA tweak)
mkdir -p /home/$USERNAME/.config/hypr
cat > /home/$USERNAME/.config/hypr/hyprland.conf <<HYPRCONF
env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = WLR_NO_HARDWARE_CURSORS,1
env = __GLX_VENDOR_LIBRARY_NAME,nvidia

monitor=*
refresh_rate=144

render_force_software_cursor=true

vsync=on
HYPRCONF

chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

# Setup Looking Glass client config
mkdir -p /home/$USERNAME/.config/looking-glass
cat > /home/$USERNAME/.config/looking-glass/client.ini <<LGCONF
[app]
inputGrab=true
escapeKey=KEY_RIGHTCTRL
LGCONF

chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/looking-glass

# Add alias for Looking Glass client
echo "alias lg='looking-glass-client -m -f'" >> /home/$USERNAME/.bashrc

# VFIO bind script
cat > /usr/local/bin/vfio-bind.sh <<VFIO
#!/bin/bash
if [ "\$#" -lt 2 ]; then
  echo "Usage: sudo vfio-bind.sh <GPU PCI ID> <Audio PCI ID>"
  exit 1
fi

GPU_PCI=\$1
AUDIO_PCI=\$2

echo "Binding GPU \$GPU_PCI and Audio \$AUDIO_PCI to vfio-pci driver"

for DEV in \$GPU_PCI \$AUDIO_PCI; do
  echo "Unbinding device \$DEV from current driver"
  echo \$DEV | tee /sys/bus/pci/devices/\$DEV/driver/unbind

  echo "Binding device \$DEV to vfio-pci"
  echo vfio-pci | tee /sys/bus/pci/devices/\$DEV/driver_override
  echo \$DEV | tee /sys/bus/pci/drivers_probe
done

echo "VFIO binding complete."
VFIO

chmod +x /usr/local/bin/vfio-bind.sh

# --- JA KOOLIT INSTALL ---

su - $USERNAME -c "
git clone https://github.com/JaKooLit/JaKooLit.git /home/$USERNAME/JaKooLit
cd /home/$USERNAME/JaKooLit
chmod +x install.sh
./install.sh
"

EOF

echo
echo "Installation finished! You can now reboot."
echo "Login as $USERNAME."
echo "Don't forget to disable Secure Boot and set MUX switch to discrete GPU in BIOS."
echo
