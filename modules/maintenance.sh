#!/bin/bash

# Cleanup- und Wartungsfunktionen für AI-Stack
function cleanup_menu() {
  # Sicherstellen, dass wichtige Variablen vorhanden sind
  COMPOSE_FILE="${COMPOSE_FILE:-$PROJECT_DIR/docker-compose.yml}"
  LVM_VOLUME="${VOLUME_DEVICE:-}"
  if [[ -z "$LVM_VOLUME" ]]; then
    echo "❌ Kein LVM-Volume definiert (VOLUME_DEVICE fehlt)."
    return
  fi

  PS3="Bitte Bereinigungsoption wählen: "
  options=(
    "SCRIPT_DIR löschen (vollständig)"
    "PROJECT_DIR löschen (Modelle, Daten etc.)"
    "LVM-Volume löschen"
    "Nur Docker-Container löschen"
    "Alles außer Volumes löschen (Models & Daten bleiben)"
    "Zurück"
  )

  select opt in "${options[@]}"; do
    case $REPLY in
      1)
        read -rp "SCRIPT_DIR '$SCRIPT_DIR' wirklich löschen? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Abgebrochen."; break; }
        sudo rm -rf "$SCRIPT_DIR"
        echo "SCRIPT_DIR gelöscht."
        break
        ;;
      2)
        read -rp "PROJECT_DIR '$PROJECT_DIR' wirklich löschen? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Abgebrochen."; break; }
        sudo rm -rf "$PROJECT_DIR"
        echo "PROJECT_DIR gelöscht."
        break
        ;;
      3)
        read -rp "LVM-Volume '$LVM_VOLUME' wirklich löschen? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Abgebrochen."; break; }
        sudo lvremove -f "$LVM_VOLUME"
        echo "LVM-Volume gelöscht."
        break
        ;;
      4)
        read -rp "Alle Docker-Container stoppen und löschen (Modelle bleiben)? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Abgebrochen."; break; }
        docker compose -f "$COMPOSE_FILE" down
        echo "Docker-Container gestoppt und gelöscht."
        break
        ;;
      5)
        read -rp "Alle Nicht-Volume-Daten in '$PROJECT_DIR' löschen? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Abgebrochen."; break; }

        keep_paths=(
          "$PROJECT_DIR/data"
          "$PROJECT_DIR/volumes"
          "$PROJECT_DIR/models"
        )

        echo "Lösche alle Dateien in $PROJECT_DIR außer Volumes..."
        shopt -s dotglob
        for item in "$PROJECT_DIR"/*; do
          skip=false
          for keep in "${keep_paths[@]}"; do
            [[ "$item" == "$keep" ]] && skip=true
          done
          $skip || sudo rm -rf "$item"
        done
        shopt -u dotglob

        echo "Nicht-Volume-Daten gelöscht."
        break
        ;;
      6)
        echo "Zurück zum Wartungsmenü."
        break
        ;;
      *)
        echo "Ungültige Auswahl.";;
    esac
  done
}
# Wartungsoptionen für Container und Dienste

show_maintenance_menu() {
  echo "🔧 Wartungstools:"
  echo "1) Container stoppen und entfernen"
  echo "2) Modelle neu laden und initialisieren"
  echo "3) Healthcheck Modelle"
  echo "4) System bereinigen"
  echo "q) Beenden"
  echo -n "> Auswahl: "
}

get_container_name() {
  local pattern="$1"
  docker ps --format '{{.Names}}' | grep "$pattern" | head -n1
}

while true; do
  show_maintenance_menu
  read -r option
  case "$option" in
    1)
      echo "🛑 Container stoppen und löschen..."
      docker compose down
      ;;
    2)
      echo "⬇️ Modelle neu pullen und initialisieren..."
      declare -A MODEL_SERVICE_NAMES=(
        [mistral]=ollama-mistral
        [mixtral]=ollama-mixtral
        [command-r]=ollama-commandr
        [yi]=ollama-yib
        [openhermes]=ollama-hermes
        [nous-hermes2]=ollama-nous
      )
      for model in "${!MODEL_SERVICE_NAMES[@]}"; do
        container=$(get_container_name "${MODEL_SERVICE_NAMES[$model]}")
        if [[ -n "$container" ]]; then
          echo "🔁 Pull: $model ($container)"
          docker exec "$container" ollama pull "$model"
        fi
      done

      echo "🤖 Initialisiere Modelle mit Testprompt..."

      declare -A MODEL_PORTS=(
        [mistral]=11431
        [mixtral]=11432
        [command-r]=11433
        [yi]=11434
        [openhermes]=11435
        [nous-hermes2]=11436
      )

      for model in "${!MODEL_PORTS[@]}"; do
        port="${MODEL_PORTS[$model]}"
        echo -e "\n🧠 $model (Port $port)"
        echo "📨 Prompt: Hallo"
        response=$(curl -s http://localhost:$port/api/generate \
          -H "Content-Type: application/json" \
          -d "{\"model\": \"$model\", \"prompt\": \"Hallo\", \"stream\": false}")
        answer=$(echo "$response" | jq -r '.response // "❌ Keine Antwort (Fehler?)"')
        echo "📬 Antwort: $answer"
      done
      ;;
    3)
      echo "❤️ Healthcheck der Modelle..."
      declare -A MODEL_PORTS=(
        [mistral]=11431
        [mixtral]=11432
        [command-r]=11433
        [yi]=11434
        [openhermes]=11435
        [nous-hermes2]=11436
      )
      for model in "${!MODEL_PORTS[@]}"; do
        port=${MODEL_PORTS[$model]}
        echo "📡 Teste $model auf Port $port..."
        curl -s http://localhost:$port/api/generate \
          -H "Content-Type: application/json" \
          -d "{\"model\": \"$model\", \"prompt\": \"ping\", \"stream\": false}" | jq -r .response
      done
      ;;
    4) 
      cleanup_menu
    ;;
    q|Q)
      break
      ;;
    *)
      echo "❌ Ungültige Eingabe."
      ;;
  esac
  echo ""
done

