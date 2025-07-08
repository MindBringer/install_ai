#!/bin/bash
# Wartungsoptionen für Container und Dienste

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_maintenance_menu() {
  echo "🔧 Wartungstools:"
  echo "1) Container stoppen und entfernen"
  echo "2) Modelle neu laden und initialisieren"
  echo "3) Healthcheck Modelle"
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
    q|Q)
      break
      ;;
    *)
      echo "❌ Ungültige Eingabe."
      ;;
  esac
  echo
