#!/bin/bash
set -euo pipefail

# Funktion zur Prüfung von Kommandos
check_command() {
  local cmd_output
  if cmd_output="$($@ 2>&1)"; then
    echo "✅ Befehl erfolgreich: $*"
  else
    echo "❌ Fehler: $*"
    echo "$cmd_output"
    return 1
  fi
}

# Systemvorbereitung: Tools, Docker, Volume...
echo "[MODUL] setup-system"

### === [1/8] System vorbereiten ===
echo "[1/8] 🛠️  Aktualisiere System & installiere Grundtools..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  nano git curl jq wget gnupg lsb-release \
  ca-certificates apt-transport-https \
  software-properties-common iproute2 net-tools \
  iputils-ping traceroute htop lsof npm unzip ufw

sudo npm install -g n
sudo n lts
npm install --save-dev typescript @types/react @types/react-dom @react-keycloak/web keycloak-js

### === [2/8] Docker & Compose ===
echo "[2/8] 🐳 Installiere Docker & Compose..."
check_command sudo install -m 0755 -d /etc/apt/keyrings
check_command sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
check_command sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

TARGET_USER="${SUDO_USER:-$USER}"
sudo usermod -aG docker "$TARGET_USER"

echo "🔎 Prüfe Docker-Gruppenzugehörigkeit..."
if ! groups "$TARGET_USER" | grep -qw docker; then
  echo "❌ Benutzer '$TARGET_USER' ist nicht in der Gruppe 'docker'."
  echo "➡️  Bitte ausführen: sudo usermod -aG docker $TARGET_USER"
  exit 1
else
  echo "✅ Benutzer '$TARGET_USER' ist in der Docker-Gruppe."
fi

echo "🔧 Richte Docker-Volume ein..."
DOCKER_LV_NAME="docker"
DOCKER_MOUNT="/docker"
VG_NAME=$(sudo vgs --noheadings -o vg_name | awk '{print $1}')
LV_PATH="/dev/${VG_NAME}/${DOCKER_LV_NAME}"

# Prüfen, ob Volume existiert
if sudo lvdisplay "$LV_PATH" >/dev/null 2>&1; then
    echo "📦 LVM-Volume '$DOCKER_LV_NAME' existiert bereits."

    # Prüfen, ob gemountet
    if mountpoint -q "$DOCKER_MOUNT"; then
        echo "✅ Volume ist bereits gemountet unter $DOCKER_MOUNT – Setup wird übersprungen."
    else
        echo "⚠️ Volume ist nicht gemountet – mounte erneut..."
        sudo mkdir -p "$DOCKER_MOUNT"
        sudo mount "$LV_PATH" "$DOCKER_MOUNT"
        USER_UID=$(id -u "${SUDO_USER:-$USER}")
        USER_GID=$(id -g "${SUDO_USER:-$USER}")
        sudo chown -R "${USER_UID}:${USER_GID}" "${DOCKER_MOUNT}"
    fi

else
    echo "📦 Erstelle neues Docker-Volume über LVM..."
    sudo bash ./modules/setup-docker-volume.sh
fi

