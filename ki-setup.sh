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
  nano git curl wget gnupg lsb-release \
  ca-certificates apt-transport-https \
  software-properties-common iproute2 net-tools \
  iputils-ping traceroute htop lsof npm unzip ufw

sudo npm install -g n
sudo n lts

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

### === [3/8] Verzeichnisse & Dateien ===
echo "[3/8] 📁 Projektverzeichnis vorbereiten..."
PROJECT_DIR="$HOME/ai-stack"
mkdir -p "$PROJECT_DIR/RAG" "$PROJECT_DIR/embed-service" "$PROJECT_DIR/public" "$PROJECT_DIR/frontend-nginx/dist" "$PROJECT_DIR/n8n"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "🛠️ Erzeuge erweitertes n8n-Image mit breiter Dokumenten-Unterstützung..."
touch "$PROJECT_DIR/n8n/Dockerfile"
cat <<EOF > "$PROJECT_DIR/n8n/Dockerfile"
FROM n8nio/n8n

USER root
RUN apk add --no-cache \
  poppler-utils \
  bash \
  coreutils \
  pandoc \
  html2text \
  unrtf \
  tesseract-ocr
USER node
EOF

if [ ! -f .env ]; then
  cat <<EOD > .env
EMBEDDING_URL=http://embedding:8000
EMBEDDING_API_KEY=YOUR_API_KEY_HERE
QDRANT_URL=http://qdrant:6333
WHISPER_HF_TOKEN=hf_xxxxxxxxxxxxx
VITE_API_BASE_URL=http://api.local
VITE_AZURE_CLIENT_ID=...
VITE_AZURE_TENANT_ID=...
EOD
  echo "⚠️ .env Dummy angelegt – bitte anpassen!"
fi
export $(grep -v '^[[:space:]]*#' .env | xargs)

### === Dateien kopieren ===
echo "[4/8] 📂 Dateien vorbereiten..."
cp "$SCRIPT_DIR/docker/docker-compose.yml" "$PROJECT_DIR/"
cp "$SCRIPT_DIR/docker/frontend-nginx/Dockerfile" "$PROJECT_DIR/frontend-nginx/"
cp "$SCRIPT_DIR/docker/frontend-nginx/nginx.conf" "$PROJECT_DIR/frontend-nginx/"
cp "$SCRIPT_DIR/embed-service/"* "$PROJECT_DIR/embed-service/"
cp "$SCRIPT_DIR/RAG/"* "$PROJECT_DIR/RAG/"

cd "$SCRIPT_DIR/docker/Frontend"
[ ! -d node_modules ] && npm install
npm run build
cp -r dist/* "$PROJECT_DIR/frontend-nginx/dist/"

### === [5/8] 🌐 Erzeuge Caddyfile ===
echo "[5/8] 🌐 Erzeuge Caddyfile für Subdomain-Reverse-Proxy..."
cat <<EOF > "$PROJECT_DIR/Caddyfile"
{
  auto_https off
  admin off
}

http://chat.local {
  reverse_proxy localhost:8080
  tls internal
}

http://n8n.local {
  reverse_proxy localhost:5678
  tls internal
}

http://whisper.local {
  reverse_proxy localhost:9000
  tls internal
}

http://ollama.local {
  reverse_proxy localhost:11434
  tls internal
}

http://api.local {
  reverse_proxy localhost:80
  tls internal
}

http://rag.local {
  reverse_proxy localhost:8001
  tls internal
}

http://docs.local {
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
if ! docker info &>/dev/null; then
  echo "❌ Docker ist nicht verfügbar für den aktuellen Benutzer."
  echo "💡 Bitte führe 'newgrp docker' aus oder logge dich neu ein."
  echo "❌ Abbruch."
  exit 1
fi

echo "[7/8] 🚀 Starte Container phasenweise..."
docker compose build

## Phase 1
echo "➡️ Phase 1: qdrant, ollama, embedding, open-webui, tester"
docker compose up -d qdrant ollama embedding open-webui tester
sleep 10
echo "🔍 Prüfe Phase 1..."
docker exec tester curl -fs http://qdrant:6333/ && echo "✅ Qdrant erreichbar" || echo "❌ Qdrant nicht erreichbar"
docker exec tester curl -fs http://ollama:11434/ && echo "✅ Ollama erreichbar" || echo "❌ Ollama nicht erreichbar"
docker exec tester curl -fs http://open-webui:8080/ && echo "✅ WebUI erreichbar" || echo "❌ WebUI nicht erreichbar"
echo "🤖 Initialisiere mistral..."
docker exec ollama ollama pull mistral || true
echo "Hallo" | docker exec -i ollama ollama run mistral || true
read -p "⏭️ Weiter mit Phase 2? [Enter]"

## Phase 2
echo "➡️ Phase 2: rag-upload, whisper, n8n"
docker compose up -d rag-upload whisper n8n
sleep 10
docker exec tester curl -fs http://whisper:9000/docs && echo "✅ Whisper erreichbar" || echo "❌ Whisper nicht erreichbar"
docker exec tester curl -fs http://rag-upload:8001/ && echo "✅ Upload-API erreichbar" || echo "❌ Upload-API nicht erreichbar"
docker exec tester curl -fs http://n8n:5678/ && echo "✅ n8n erreichbar" || echo "❌ n8n nicht erreichbar"
read -p "⏭️ Weiter mit Phase 3? [Enter]"

## Phase 3
echo "➡️ Phase 3: frontend, caddy"
docker compose up -d frontend caddy
sleep 5
echo "🌐 Zugriff über Subdomains (DNS oder /etc/hosts nötig):"
echo " - http://chat.local         → Open WebUI"
echo " - http://n8n.local          → n8n Workflowsystem"
echo " - http://whisper.local/docs → Whisper ASR"
echo " - http://ollama.local       → Ollama API"
echo " - http://rag.local          → Upload-UI"
echo " - http://api.local          → React Frontend"
echo " - http://docs.local         → Filebrowser (statisch)"
echo " - http://<Server-IP>        → statische Inhalte"

### === [8/8] Dienste-Check ===
echo "[8/8] ✅ Finaler Dienste-Check folgt manuell nach Phase 3"
echo "🎉 Setup abgeschlossen. Jetzt kannst du den Stack nutzen."
echo "📄 Trage evtl. noch Hosts-Einträge auf deinen Clients ein."
echo "Fertig!"
