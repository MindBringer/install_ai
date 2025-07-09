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

# Container phasenweise starten, Modelle prüfen...
echo "[MODUL] start-container"
### === [7/8] Container phasenweise starten ===
echo "🧪 Teste Docker-Verfügbarkeit ohne Root..."
cd "$PROJECT_DIR"
if ! docker info &>/dev/null; then
  echo "❌ Docker ist nicht verfügbar für den aktuellen Benutzer."
  echo "💡 Bitte führe 'newgrp docker' aus oder logge dich neu ein."
  echo "❌ Abbruch."
  exit 1
fi

echo "[7/8] 🚀 Starte Container phasenweise..."
docker compose build

## Phase 1
echo "➡️ Phase 1: qdrant, ollama mit Modellen, embedding, tester"
docker compose up -d qdrant ollama-commandr ollama-hermes ollama-mistral ollama-mixtral ollama-nous ollama-yib tester
sleep 10
echo "🔍 Prüfe Phase 1..."
docker exec tester curl -fs http://qdrant:6333/ && echo "✅ Qdrant erreichbar" || echo "❌ Qdrant nicht erreichbar"

echo "⬇️ Lade Modelle direkt im Container (Ollama CLI)..."

declare -A MODEL_SERVICE_NAMES=(
  [mistral]=ollama-mistral
  [mixtral]=ollama-mixtral
  [command-r]=ollama-commandr
  [yi]=ollama-yib
  [openhermes]=ollama-hermes
  [nous-hermes2]=ollama-nous
)

for model in "${!MODEL_SERVICE_NAMES[@]}"; do
  service_name="${MODEL_SERVICE_NAMES[$model]}"
  container=$(docker ps --format '{{.Names}}' | grep "$service_name" | head -n1)

  if [[ -z "$container" ]]; then
    echo "⚠️  Container für '$service_name' nicht gefunden – überspringe '$model'"
    continue
  fi

  echo "⬇️  Pull für Modell '$model' im Container '$container'..."
  docker exec "$container" ollama pull "$model"
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
read -p "⏭️ Weiter mit Phase 2? [Enter]"

## Phase 2
echo "➡️ Phase 2: haystack, crewAI, whisperx, n8n"
docker compose up -d whisperx n8n haystack crewai
sleep 10
docker exec tester curl -fs http://whisperx:9000/docs && echo "✅ Whisper erreichbar" || echo "❌ Whisper nicht erreichbar"
docker exec tester curl -fs http://n8n:5678/ && echo "✅ n8n erreichbar" || echo "❌ n8n nicht erreichbar"
read -p "⏭️ Weiter mit Phase 3? [Enter]"

## Phase 3
echo "➡️ Phase 3: frontend, caddy"
docker compose up -d frontend caddy
sleep 5
echo "🌐 Zugriff über Subdomains (DNS oder /etc/hosts nötig):"
echo " - http://n8n.local          → n8n Workflowsystem"
echo " - http://whisper.local/docs → Whisper ASR"
echo " - http://ollama.local       → Ollama API"
echo " - http://api.local          → React Frontend"
echo " - http://docs.local         → Filebrowser (statisch)"
echo " - http://<Server-IP>        → statische Inhalte"

### === [8/8] Dienste-Check ===
echo "[8/8] ✅ Finaler Dienste-Check folgt manuell nach Phase 3"
echo "🎉 Setup abgeschlossen. Jetzt kannst du den Stack nutzen."
echo "📄 Trage evtl. noch Hosts-Einträge auf deinen Clients ein."
echo "Fertig!"
