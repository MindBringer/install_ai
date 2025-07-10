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

# 🔧 zentrale Verzeichnisdefinition
PROJECT_DIR="~/$HOME/ai-stack"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$PROJECT_DIR"

# 🌍 Variablen exportieren für Unterprozesse
export PROJECT_DIR
export SCRIPT_DIR

# === [Hauptmenü] ===
show_menu() {
  echo "🧠 AI-Stack Setup – Hauptmenü"
  echo "1) Systemsetup (Linux, Docker, Volume)"
  echo "2) Projektverzeichnis & Dateien kopieren"
  echo "3) Containerstart (phasenweise)"
  echo "4) Wartung & Tools"
  echo "5) Komplettinstallation (alles)"
  echo "6) Update (System, Tools, Container)"
  echo "7) Komplett-Deinstallation (hart)"
  echo "q) Beenden"
  echo -n "> Auswahl: "
}

while true; do
  show_menu
  read -r choice
  case "$choice" in
    1)
      bash "$SCRIPT_DIR/modules/setup-system.sh"
      ;;
    2)
      bash "$SCRIPT_DIR/modules/setup-projectdir.sh"
      ;;
    3)
      bash "$SCRIPT_DIR/modules/start-container.sh"
      ;;
    4)
      bash "$SCRIPT_DIR/modules/maintenance.sh"
      ;;
    5)
      bash "$SCRIPT_DIR/modules/setup-system.sh"
      bash "$SCRIPT_DIR/modules/setup-projectdir.sh"
      bash "$SCRIPT_DIR/modules/start-container.sh"
      bash "$SCRIPT_DIR/modules/maintenance.sh"
      ;;
    6)
      bash "$SCRIPT_DIR/modules/update.sh"
      ;;
    7)
      bash "$SCRIPT_DIR/modules/uninstall.sh"
      ;;
    q|Q)
      echo "👋 Beende Setup."
      exit 0
      ;;
    *)
      echo "❌ Ungültige Eingabe."
      ;;
  esac
  echo ""
done
