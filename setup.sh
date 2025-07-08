#!/bin/bash
set -euo pipefail

# === [Hauptmenü] ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_menu() {
  echo "🧠 AI-Stack Setup – Hauptmenü"
  echo "1) Systemsetup (Linux, Docker, Volume)"
  echo "2) Projektverzeichnis & Dateien kopieren"
  echo "3) Containerstart (phasenweise)"
  echo "4) Wartung & Tools"
  echo "5) Komplettinstallation (alles)"
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
