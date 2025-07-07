#!/bin/bash
set -e

DOCKER_LV_NAME="docker"
DOCKER_MOUNT="/docker"
DOCKER_DATA_DIR="$DOCKER_MOUNT/docker-data"
VG_NAME=$(vgs --noheadings -o vg_name | awk '{print $1}')
DOCKER_SIZE="1T"

echo "📦 Erstelle LVM-Volume für Docker-Daten..."

# Prüfen, ob Volume bereits existiert
if lvdisplay /dev/${VG_NAME}/${DOCKER_LV_NAME} >/dev/null 2>&1; then
    echo "✅ Volume ${DOCKER_LV_NAME} existiert bereits."
else
    sudo lvcreate -L $DOCKER_SIZE -n $DOCKER_LV_NAME $VG_NAME
    sudo mkfs.ext4 /dev/${VG_NAME}/${DOCKER_LV_NAME}
    echo "✅ Volume ${DOCKER_LV_NAME} mit ${DOCKER_SIZE} erstellt."
fi

# Mountpunkt erstellen und eintragen
sudo mkdir -p "$DOCKER_DATA_DIR"
if ! grep -q "${DOCKER_MOUNT}" /etc/fstab; then
    echo "/dev/${VG_NAME}/${DOCKER_LV_NAME} ${DOCKER_MOUNT} ext4 defaults 0 2" | sudo tee -a /etc/fstab
fi

echo "⏳ Mounten..."
sudo mount "${DOCKER_MOUNT}"
# Setze Besitzrechte für normalen Benutzer
USER_UID=$(id -u "${SUDO_USER:-$USER}")
USER_GID=$(id -g "${SUDO_USER:-$USER}")
sudo chown -R "${USER_UID}:${USER_GID}" "${DOCKER_MOUNT}"

# Docker stoppen und Daten verschieben
echo "🛑 Stoppe Docker..."
sudo systemctl stop docker

if [ -d /var/lib/docker ]; then
    echo "📁 Verschiebe bestehende Docker-Daten..."
    sudo rsync -aHAXx /var/lib/docker/ "${DOCKER_DATA_DIR}/"
fi

# Docker Konfiguration setzen
echo "⚙️ Konfiguriere Docker auf neuen Pfad..."
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "data-root": "${DOCKER_DATA_DIR}"
}
EOF

# Starte Docker neu
echo "🚀 Starte Docker neu..."
sudo systemctl start docker

# Prüfen
docker info | grep "Docker Root Dir"

echo "✅ Docker verwendet nun: ${DOCKER_DATA_DIR}"