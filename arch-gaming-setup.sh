#!/bin/bash
set -e

echo "==> Updating system..."
sudo pacman -Syu --noconfirm

echo "==> Installing GPU drivers (Intel iGPU + NVIDIA 4070 MAX-Q)..."
sudo pacman -S --noconfirm \
    mesa vulkan-intel libva-intel-driver libva-utils intel-media-driver \
    nvidia nvidia-utils nvidia-settings lib32-nvidia-utils opencl-nvidia \
    linux-headers nvidia-prime

echo "==> Enabling NVIDIA offloading for hybrid graphics..."
sudo bash -c 'cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_PreserveVideoMemoryAllocations=1
EOF'

echo "==> Installing essential gaming tools..."
# Install core gaming packages from official repos
sudo pacman -S --noconfirm \
    steam heroic-games-launcher mangohud goverlay gamescope \
    lutris wine winetricks gamemode lib32-gamemode \
    vulkan-tools lib32-vulkan-icd-loader vulkan-icd-loader

# Install vkBasalt and 32-bit variant from AUR using yay
yay -S --noconfirm vkbasalt lib32-vkbasalt


echo "==> Installing Proton GE (custom version)..."
mkdir -p ~/.steam/root/compatibilitytools.d
cd /tmp && yay -S --noconfirm proton-ge-custom-bin
cd ~

echo "==> Enabling Steam Play in config (if missing)..."
mkdir -p ~/.steam/root
echo '{"compat_tool":"proton-ge-custom"}' > ~/.steam/root/config/config.vdf

echo "==> Installing virtualization tools with QEMU + GPU Passthrough..."
sudo pacman -S --noconfirm \
    qemu-full virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat \
    edk2-ovmf swtpm spice spice-gtk ebtables iptables-nft ovmf

echo "==> Enabling libvirtd and configuring user access..."
sudo systemctl enable --now libvirtd.service
sudo usermod -aG libvirt $(whoami)

echo "==> Installing Looking Glass for VM display mirroring..."
yay -S --noconfirm looking-glass-git looking-glass-module-dkms

echo "==> Installing additional performance & monitoring tools..."
sudo pacman -S --noconfirm \
    htop btop cpupower powertop piper corectrl nvtop

echo "==> Setting CPU governor to performance..."
sudo systemctl enable --now cpupower
sudo bash -c 'echo "governor=performance" > /etc/default/cpupower'

echo "==> Disabling KDE/Gnome junk (already using Hyprland)..."
sudo pacman -Rns --noconfirm kdeconnect packagekit

echo "==> Final system cleanup..."
yay -Yc --noconfirm

echo "==> Done! Reboot your system now to complete setup."
