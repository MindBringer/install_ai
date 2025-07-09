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

echo "🔄 Starte Update-Prozess für System, Tools und Container..."

### === 1. Systemupdates ===
echo "📦 Aktualisiere Linux-Pakete..."
sudo apt update
sudo apt -y upgrade
sudo apt -y dist-upgrade
sudo apt -y autoremove

### === 2. Node.js & Tools ===
echo "🧰 Aktualisiere node.js & globale npm-Tools..."
sudo npm install -g n
sudo n lts

echo "📦 Aktualisiere lokale Dev-Abhängigkeiten (falls vorhanden)..."
if [ -f package.json ]; then
  npm install
fi

### === 3. Docker selbst ===
echo "🐳 Prüfe Docker-Version..."
docker_version=$(docker --version)
echo "🔍 Installierte Docker-Version: $docker_version"

### === 4. Docker-Images aktualisieren ===
echo "⬇️ Aktualisiere Docker-Images aus docker-compose..."
cd "$PROJECT_DIR"

if [ -f docker-compose.yml ]; then
  docker compose pull
  echo "🔁 Container neustarten?"
  read -rp "➕ Möchtest du alle Container neu starten? (y/N): " restart_choice
  if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
    docker compose up -d
    echo "✅ Container neu gestartet."
  else
    echo "⚠️ Container wurden nicht neu gestartet."
  fi
else
  echo "❌ Keine docker-compose.yml gefunden unter $PROJECT_DIR – überspringe Container-Update."
fi

echo "✅ Update abgeschlossen."
