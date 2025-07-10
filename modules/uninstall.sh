#!/bin/bash
set -euo pipefail

# Hartes Deinstallations-Skript für Testsysteme mit AI-Stack
# Achtung: löscht unwiderruflich Daten, Volumes, Container, Verzeichnisse

echo "⚠️  Starte radikale Deinstallation des AI-Stacks..."

# Dienste stoppen
echo "🛑 Stoppe laufende Container und Docker..."
docker ps -q | xargs -r docker stop || true
docker ps -aq | xargs -r docker rm -f || true
docker volume ls -q | xargs -r docker volume rm -f || true
docker network prune -f || true
systemctl stop docker || true

# Docker deinstallieren
if command -v apt &>/dev/null; then
  echo "🧹 Entferne Docker über apt..."
  apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
  apt autoremove -y || true
fi

# Projektverzeichnis löschen
PROJECT_DIR="~/home/jan/ai-stack"
echo "🗑️  Entferne Projektverzeichnis: $PROJECT_DIR"
rm -rf "$PROJECT_DIR"

# Laufwerke löschen (logisches Docker-Volume suchen und aushängen)
echo "🧼 Prüfe und entferne ggf. LVM Docker-Volumes..."
DOCKER_LV=$(lsblk -o NAME,MOUNTPOINT | grep "/var/lib/docker" | awk '{print $1}')
if [ -n "$DOCKER_LV" ]; then
  MAPPER_NAME=$(lsblk -no NAME "/dev/$DOCKER_LV")
  echo "🚨 Lösche logisches Volume: $MAPPER_NAME"
  lvremove -f "/dev/mapper/$MAPPER_NAME" || true
fi

# Installationsverzeichnis löschen
SCRIPT_DIR="~/home/jan/install_ai"
echo "🗑️  Entferne Installationsverzeichnis: $SCRIPT_DIR"
rm -rf "$SCRIPT_DIR"

# Prüfung: sind alle entfernt?
echo "🔍 Prüfe verbleibende Reste..."
[[ -d "$PROJECT_DIR" ]] && echo "❌ Projektverzeichnis existiert noch!" || echo "✅ Projektverzeichnis entfernt"
[[ -d "$SCRIPT_DIR" ]] && echo "❌ Installationsverzeichnis existiert noch!" || echo "✅ Installationsverzeichnis entfernt"
docker ps -a && echo "⚠️  Noch Container aktiv!" || echo "✅ Keine Container mehr aktiv"
docker volume ls && echo "⚠️  Noch Volumes vorhanden!" || echo "✅ Keine Docker-Volumes mehr vorhanden"

echo "🎉 Radikale Deinstallation abgeschlossen."