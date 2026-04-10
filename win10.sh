#!/bin/bash
set -euo pipefail

# =========================
# CONFIG
# =========================
DISK="/dev/sda"
PART1="${DISK}1"
PART2="${DISK}2"

WIN_ISO_URL="https://bit.ly/4aCjkM2"
WIN_ISO_NAME="win10.iso"

VIRTIO_ISO_URL="https://bit.ly/4d1g7Ht"
VIRTIO_ISO_NAME="virtio.iso"

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

MNT="/mnt"
WINDISK="/root/windisk"
ISO_MOUNT="${WINDISK}/winfile"

# =========================
# WARN
# =========================
echo "[!] WARNING: This will completely erase ${DISK}"
sleep 3

# =========================
# INSTALL REQUIRED PACKAGES
# =========================
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y grub2 wimtools ntfs-3g gdisk parted rsync wget

# =========================
# CLEANUP FUNCTION
# =========================
cleanup() {
    set +e
    umount "${ISO_MOUNT}" 2>/dev/null || true
    umount "${MNT}" 2>/dev/null || true
}
trap cleanup EXIT

# =========================
# PREPARE DISK
# =========================
umount "${PART1}" 2>/dev/null || true
umount "${PART2}" 2>/dev/null || true

parted "${DISK}" --script mklabel gpt
parted "${DISK}" --script mkpart primary ntfs 1MiB 51200MiB
parted "${DISK}" --script mkpart primary ntfs 51200MiB 92160MiB

partprobe "${DISK}"
sleep 5

mkfs.ntfs -f "${PART1}"
mkfs.ntfs -f "${PART2}"

echo "[+] NTFS partitions created"

# Hybrid MBR for BIOS boot compatibility
echo -e "r\ng\np\nw\nY\n" | gdisk "${DISK}"

sleep 3
partprobe "${DISK}"
sleep 3

# =========================
# MOUNT PARTITIONS
# =========================
mkdir -p "${MNT}"
mount "${PART1}" "${MNT}"

mkdir -p "${WINDISK}"
mkdir -p "${ISO_MOUNT}"
mount "${PART2}" "${WINDISK}"

# =========================
# INSTALL GRUB
# =========================
grub-install --target=i386-pc --boot-directory="${MNT}/boot" "${DISK}"

cat > "${MNT}/boot/grub/grub.cfg" <<'EOF'
menuentry "windows installer" {
    insmod ntfs
    search --set=root --file /bootmgr
    ntldr /bootmgr
    boot
}
EOF

echo "[+] GRUB installed"

# =========================
# DOWNLOAD WINDOWS ISO
# =========================
cd "${WINDISK}"

wget -O "${WIN_ISO_NAME}" --user-agent="${USER_AGENT}" "${WIN_ISO_URL}"

# =========================
# COPY WINDOWS FILES
# =========================
mount -o loop "${WIN_ISO_NAME}" "${ISO_MOUNT}"
rsync -avh --progress "${ISO_MOUNT}/" "${MNT}/"
umount "${ISO_MOUNT}"

echo "[+] Windows installer files copied"

# =========================
# DOWNLOAD VIRTIO ISO
# =========================
wget -O "${VIRTIO_ISO_NAME}" "${VIRTIO_ISO_URL}"

mount -o loop "${VIRTIO_ISO_NAME}" "${ISO_MOUNT}"

mkdir -p "${MNT}/sources/virtio"
rsync -avh --progress "${ISO_MOUNT}/" "${MNT}/sources/virtio/"
umount "${ISO_MOUNT}"

echo "[+] VirtIO drivers copied"

# =========================
# INJECT VIRTIO INTO BOOT.WIM
# =========================
cd "${MNT}/sources"

cat > cmd.txt <<'EOF'
add virtio /virtio_drivers
EOF

wimlib-imagex update boot.wim 2 < cmd.txt

echo "[+] boot.wim updated with VirtIO drivers"

sync

echo "[+] Done"
echo "[+] Reboot when ready"
# reboot
