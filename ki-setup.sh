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

### === [3/8] Verzeichnisse & Dateien ===
echo "[3/8] 📁 Projektverzeichnis vorbereiten..."
PROJECT_DIR="$HOME/ai-stack"
mkdir -p "$PROJECT_DIR/keycloak"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if [ ! -f .env ]; then
  cat <<EOD > .env
EMBEDDING_URL=http://embedding:8000
EMBEDDING_API_KEY=YOUR_API_KEY_HERE
QDRANT_URL=http://qdrant:6333
WHISPER_HF_TOKEN=hf_xxxxxxxxxxxxx
VITE_API_BASE_URL=http://api.local
VITE_KEYCLOAK_URL=https://auth.local
VITE_KEYCLOAK_REALM=mein-unternehmen
VITE_KEYCLOAK_CLIENT_ID=frontend
EOD
  echo "⚠️ .env Dummy angelegt – bitte anpassen!"
fi
export $(grep -v '^[[:space:]]*#' .env | xargs)

### === [4/8] Dateien kopieren ===
echo "[4/8] 📂 Dateien vorbereiten..."
cp "$SCRIPT_DIR/docker/docker-compose.yml" "$PROJECT_DIR/docker-compose.yml"

# Kopiere frontend-nginx-Dateien
mkdir -p "$PROJECT_DIR/frontend-nginx"
cp "$SCRIPT_DIR/docker/frontend-nginx/Dockerfile" "$PROJECT_DIR/frontend-nginx/"
cp "$SCRIPT_DIR/docker/frontend-nginx/nginx.conf" "$PROJECT_DIR/frontend-nginx/"

# Kopiere n8n-Dateien
mkdir -p "$PROJECT_DIR/n8n"
cp -r "$SCRIPT_DIR/docker/n8n/." "$PROJECT_DIR/n8n/"

# Kopiere whisperX-Dateien
mkdir -p "$PROJECT_DIR/whisperx"
cp -r "$SCRIPT_DIR/docker/whisperx/." "$PROJECT_DIR/whisperx/"

# Kopiere haystack-Dateien
mkdir -p "$PROJECT_DIR/haystack"
cp -r "$SCRIPT_DIR/docker/haystack/." "$PROJECT_DIR/haystack/"

# Kopiere crewAI-Dateien
mkdir -p "$PROJECT_DIR/crewai"
cp -r "$SCRIPT_DIR/docker/crewai/." "$PROJECT_DIR/crewai/"

# Kopiere Frontend build
cd "$SCRIPT_DIR/docker/frontend"
[ ! -d node_modules ] && npm install
npm run build
cp -r dist/* "$PROJECT_DIR/frontend-nginx/dist/"

### === [5/8] 🌐 Erzeuge Caddyfile ===
echo "[5/8] 🌐 Erzeuge Caddyfile für Subdomain-Reverse-Proxy..."
cat <<EOF > "$PROJECT_DIR/Caddyfile"
{
  auto_https disable_redirects
  local_certs
  admin off
}

chat.local {
  reverse_proxy localhost:11431
  tls internal
}

n8n.local {
  reverse_proxy localhost:5678
  tls internal
}

whisper.local {
  reverse_proxy localhost:9000
  tls internal
}

api.local {
  reverse_proxy localhost:80
  tls internal
}

docs.local {
  root * /srv/html
  file_server browse
  tls internal
}
EOF

### === [6/8] Firewall vorbereiten ===
echo "[6/8] 🔐 Konfiguriere Firewall..."
if command -v ufw &>/dev/null; then
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow 5678/tcp
  sudo ufw allow 8080/tcp
  sudo ufw allow 6333/tcp
  sudo ufw allow 8001/tcp
  sudo ufw allow 9000/tcp
  sudo ufw allow 11434/tcp
  sudo ufw --force enable || true
fi

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

# Model-Prüfroutinen:
# 🔍 Holt dynamisch den echten Container-Namen zu einem Ollama-Service
get_container_name() {
  local service_pattern="$1"
  docker ps --format '{{.Names}}' | grep "$service_pattern" | head -n1
}

# ❌ Container stoppen & löschen (falls vorhanden)
stop_and_remove_container() {
  local container
  container=$(get_container_name "$1")
  if [ -n "$container" ]; then
    echo "🛑 Stoppe und entferne Container: $container"
    docker stop "$container" >/dev/null 2>&1 || true
    docker rm "$container" >/dev/null 2>&1 || true
  else
    echo "ℹ️ Kein laufender Container zu '$1' gefunden."
  fi
}

# 🔁 Neustarten (stop/start)
restart_container() {
  local container
  container=$(get_container_name "$1")
  if [ -n "$container" ]; then
    echo "🔁 Neustart von Container: $container"
    docker restart "$container"
  else
    echo "⚠️ Container '$1' nicht gefunden oder nicht laufend."
  fi
}

# ❤️ Health-Check via curl
check_model_api() {
  local model="$1"
  local port="$2"
  local health_url="http://localhost:${port}/api/generate"

  echo "📡 Prüfe Erreichbarkeit von $model auf Port $port..."
  response=$(curl -s -X POST "$health_url" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$model\", \"prompt\": \"ping\", \"stream\": false}")

  if echo "$response" | jq -e .response >/dev/null 2>&1; then
    echo "✅ Modell '$model' auf Port $port ist erreichbar"
  else
    echo "❌ Keine Antwort von '$model' (Port $port)"
  fi
}


read -p "⏭️ Weiter mit Phase 2? [Enter]"

## Phase 2
echo "➡️ Phase 2: haystack, crewAI, whisper, n8n"
docker compose up -d whisper n8n haystack crewai
sleep 10
docker exec tester curl -fs http://whisper:9000/docs && echo "✅ Whisper erreichbar" || echo "❌ Whisper nicht erreichbar"
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
