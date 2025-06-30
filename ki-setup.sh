#!/bin/bash
set -euo pipefail

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

### === Systemvoraussetzungen ===
echo "[1/8] 🛠️  Aktualisiere System & installiere Grundtools..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  nano git curl wget gnupg lsb-release \
  ca-certificates apt-transport-https \
  software-properties-common iproute2 net-tools \
  iputils-ping traceroute htop lsof npm unzip ufw

### === Node.js & NPM Installation ===
sudo npm install -g n
sudo n lts

### === Docker & Compose Installation + Gruppenzugriff prüfen ===
echo "[2/8] 🐳 Installiere Docker & Docker Compose..."
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

### === Docker-Gruppenzugehörigkeit prüfen ===
echo "🔎 Prüfe, ob Benutzer in der Docker-Gruppe ist..."
if ! groups "$TARGET_USER" | grep -qw docker; then
  echo "❌ Benutzer '$TARGET_USER' ist nicht in der Gruppe 'docker'."
  echo "ℹ️  Bitte ausführen: sudo usermod -aG docker $TARGET_USER"
  echo "⚠️ Danach abmelden oder 'newgrp docker' ausführen."
  exit 1
else
  echo "✅ Benutzer '$TARGET_USER' ist in der Gruppe 'docker'."
fi

### === Vorherige Testcontainer bereinigen ===
echo "[3/8] 🧹 Entferne alte Beispiel- und KI-Container, falls vorhanden..."
for name in web ollama webui open-webui rag-upload; do
  docker rm -f "$name" 2>/dev/null && echo "🧼 Entfernt: $name" || true
done

### === Projektverzeichnis vorbereiten ===
echo "[4/8] 📁 Projektverzeichnis vorbereiten..."
if [[ "$HOME" == "/home"* && -d "/root/ai-stack" ]]; then
  echo "⚠️ Achtung: Vorheriges Setup wurde unter /root/ai-stack gefunden."
  echo "💡 Möchtest du es jetzt in deinen Benutzerordner übernehmen?"
  read -p "➡️  /root/ai-stack → $HOME/ai-stack [j/N]? " -r
  if [[ $REPLY =~ ^[JjYy]$ ]]; then
    sudo mv /root/ai-stack "$HOME/"
    sudo chown -R "$USER:$USER" "$HOME/ai-stack"
    echo "✅ Setup wurde übernommen."
  fi
fi

if [[ "$HOME" == "/root" ]]; then
  echo "⚠️ ACHTUNG: Du führst das Skript gerade als root aus."
  echo "📁 Das Setup wird unter /root/ai-stack installiert, was unerwünscht sein kann."
  echo "💡 Empfehlung: Als normaler Benutzer (z. B. 'jan') mit 'newgrp docker' neu starten."
  echo "❌ Abbruch, um versehentliche Installation im root-Home zu vermeiden."
  exit 1
fi

PROJECT_DIR="$HOME/ai-stack"
mkdir -p "$PROJECT_DIR/RAG"
mkdir -p "$PROJECT_DIR/embed-service"
mkdir -p "$PROJECT_DIR/public"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

#.env prüfen oder Dummy erzeugen
if [ -f .env ]; then
  echo "Lade Umgebungsvariablen aus .env…"
else
  echo "Keine .env im Projekt-Verzeichnis gefunden – erstelle Dummy .env mit Platzhaltern"
  cat <<EOD > .env
# Beispiel .env – bitte anpassen:
EMBEDDING_URL=http://embedding:8000
EMBEDDING_API_KEY=YOUR_API_KEY_HERE
QDRANT_URL=http://qdrant:6333
WHISPER_HF_TOKEN=hf_xxxxxxxxxxxxx
VITE_API_BASE_URL=http://api.local
VITE_AZURE_CLIENT_ID=...
VITE_AZURE_TENANT_ID=...
EOD
  echo "⚠️ .env Dummy angelegt – bitte Werte in .env ergänzen!"
fi

# Export aller Variablen aus der .env
export $(grep -v '^[[:space:]]*#' .env | xargs)

### === embed-service aus Unterordner kopieren ===
echo "📂 Übernehme RAG-Komponenten aus Unterordner 'RAG'..."
EMB_SOURCE="$SCRIPT_DIR/embed-service"

for file in embed_service.py Dockerfile.embed requirements-embed.txt; do
  if [[ -f "$EMB_SOURCE/$file" ]]; then
    cp "$EMB_SOURCE/$file" "$PROJECT_DIR/embed-service/"
    echo "✅ Kopiert: $file"
  else
    echo "⚠️  Datei nicht gefunden: $EMB_SOURCE/$file"
  fi
done

### === RAG-Komponenten aus Unterordner kopieren ===
echo "📂 Übernehme RAG-Komponenten aus Unterordner 'RAG'..."
RAG_SOURCE="$SCRIPT_DIR/RAG"

for file in upload_api.py Dockerfile.upload requirements.txt; do
  if [[ -f "$RAG_SOURCE/$file" ]]; then
    cp "$RAG_SOURCE/$file" "$PROJECT_DIR/RAG/"
    echo "✅ Kopiert: $file"
  else
    echo "⚠️  Datei nicht gefunden: $RAG_SOURCE/$file"
  fi
done

### === Interfaces / Web-Oberflächen aus Unterordner kopieren ===
echo "📁 Baue das React-Frontend mit Vite..."
FRONTEND_DIR="$SCRIPT_DIR/docker/Frontend"

if [ ! -d "$FRONTEND_DIR" ]; then
  echo "❌ Frontend-Ordner fehlt: $FRONTEND_DIR"
  exit 1
fi

cd "$FRONTEND_DIR"

# Vite-Abhängigkeiten installieren
if [ ! -d node_modules ]; then
  echo "[i] Installiere Frontend-Abhängigkeiten..."
  npm install
fi

# Frontend bauen
npm run build

# Ausgabe nach ../public kopieren (muss existieren)
echo "📁 Kopiere gebaute Dateien nach ./public/"

cp -r dist/* "$PROJECT_DIR/public/"

cd "$PROJECT_DIR"


### === Docker aus Unterordner kopieren ===
echo "📂 Übernehme Docker Unterordner 'docker'..."
DCK_SOURCE="$SCRIPT_DIR/docker"

for file in docker-compose.yml; do
  if [[ -f "$DCK_SOURCE/$file" ]]; then
    cp "$DCK_SOURCE/$file" "$PROJECT_DIR/"
    echo "✅ Kopiert: $file"
  else
    echo "⚠️  Datei nicht gefunden: $DCK_SOURCE/$file"
  fi
done

### === Qdrant-Collection ggf. auf 768-Dimension setzen (echtes Mistral-Embedding) ===
echo "🧠 Stelle sicher, dass Qdrant mit Vektorlänge 768 arbeitet..."
docker exec qdrant curl -s http://localhost:6333/collections/docs | grep 'vector_size' || \
  echo "⚠️ Qdrant-Collection 'docs' ggf. manuell mit size=768 anlegen"

### === Hinweis auf echte Embeddings in upload_api.py ===
echo "📌 Hinweis: Für echte Embeddings verwende ich jetzt den Endpunkt http://ollama:11434/api/embeddings im Upload-Service."
echo "🧠 Stelle sicher, dass dein Ollama-Modell Embeddings unterstützt. (z. B. mistral, llama3)"

### === Dockerfile für n8n mit pdftotext ===
echo "🛠️ Erzeuge erweitertes n8n-Image mit breiter Dokumenten-Unterstützung..."
mkdir -p "$PROJECT_DIR/n8n"
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

### === Caddyfile für Subdomains erzeugen ===
echo "[5/8] 🌐 Erzeuge Caddyfile für Subdomain-Reverse-Proxy..."
cat <<EOF > Caddyfile
{
  auto_https off
  admin off
}

http://chat.local {
  reverse_proxy localhost:8080
}

http://n8n.local {
  reverse_proxy localhost:5678
}

http://whisper.local {
  reverse_proxy localhost:9000
}

http://ollama.local {
  reverse_proxy localhost:11434
}

http://api.local {
  reverse_proxy localhost:8081
}

http://docs.local {
  root * /srv/html
  file_server browse
}
EOF

### === Portkonflikte prüfen (alle benötigten Ports) ===
REQUIRED_PORTS=(80 8001 8080 11434 5678 9000 6333)
for port in "${REQUIRED_PORTS[@]}"; do
  echo "🔍 Prüfe, ob Port $port bereits belegt ist..."
  if sudo lsof -i :$port -sTCP:LISTEN -nP | grep -v COMMAND; then
    echo "⚠️  Port $port ist belegt. Analysiere zugehörige Prozesse..."

    # Prüfe, ob Container auf diesen Port lauscht (in anderem Kontext?)
    if ! docker ps --format '{{.Names}} {{.Ports}}' | grep -q ":$port->"; then
      echo "🔐 Der blockierende Prozess gehört vermutlich einem Container im Root-Kontext."
      container_id=$(sudo docker ps -q --filter "publish=$port")
      if [ -n "$container_id" ]; then
        echo "🧹 Entferne Root-Container mit Port $port: $container_id"
        sudo docker rm -f "$container_id"
      else
        echo "❌ Unbekannter Prozess blockiert Port $port. Bitte prüfen mit: sudo lsof -i :$port"
        exit 1
      fi
    else
      # Entferne Container im aktuellen Kontext
      docker_containers=$(docker ps --format '{{.ID}} {{.Ports}} {{.Names}}' | grep ":$port->" | awk '{print $1}')
      if [ -n "$docker_containers" ]; then
        echo "📦 Stoppe Container: $docker_containers"
        echo "$docker_containers" | xargs -r docker rm -f
        sleep 2
      fi
    fi
  else
    echo "✅ Port $port ist frei."
  fi
done

### === Docker-Verfügbarkeit prüfen ===
echo "🧪 Teste Docker-Verfügbarkeit ohne Root..."
if ! docker info &>/dev/null; then
  echo "❌ Docker ist nicht verfügbar für den aktuellen Benutzer."
  echo "💡 Bitte führe 'newgrp docker' aus oder logge dich neu ein."
  echo "❌ Abbruch."
  exit 1
fi

### === Container starten ===
docker compose build rag-upload n8n
docker compose up -d

### === Modellprüfung und Pull absichern ===
echo "🤖 Lade Standardmodell 'mistral' in Ollama..."
docker exec ollama ollama pull mistral || echo "⚠️ Pull fehlgeschlagen oder mistral bereits vorhanden."
echo "🚀 Starte mistral einmal zum Initialisieren..."
echo "Hallo" | docker exec -i ollama ollama run mistral || echo "⚠️ mistral konnte nicht initialisiert werden"

### === Qdrant Collection 'docs' anlegen (falls nötig) ===
#echo "📦 Erstelle Qdrant-Collection 'docs' (falls nicht vorhanden)..."
#curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:6333/collections/docs \
#  -H "Content-Type: application/json" \
#  -d '{"vectors":{"size":768,"distance":"Cosine"}}' || echo "⚠️  Collection möglicherweise schon vorhanden."

### === Firewall einrichten ===
echo "[7/8] 🔐 Konfiguriere UFW-Firewall (falls aktiv)..."
if command -v ufw &>/dev/null && sudo ufw status | grep -q inactive; then
  echo "➡️  UFW ist inaktiv. Aktiviere nur HTTP & SSH."
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 5678/tcp
  sudo ufw allow 8080/tcp
  sudo ufw allow 6333/tcp
  sudo ufw allow 8001/tcp
  sudo ufw allow 9000/tcp
  sudo ufw allow 11434/tcp
  sudo ufw --force enable
elif command -v ufw &>/dev/null; then
  echo "➡️  UFW ist aktiv. Erlaube Port 80, 22, 5678, 9000 und 11434."
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 5678/tcp
  sudo ufw allow 8080/tcp
  sudo ufw allow 6333/tcp
  sudo ufw allow 8001/tcp
  sudo ufw allow 9000/tcp
  sudo ufw allow 11434/tcp
fi

### === Verfügbarkeitsprüfung aller Dienste ===
echo "[8/8] ✅ Prüfe Verfügbarkeit der Dienste im lokalen Netzwerk..."

SERVICES=(
  "WebUI:http://open-webui:8080"
  "n8n:http://n8n:5678"
  "Whisper:http://whisper:9000/docs"
  "Ollama:http://ollama:11434"
  "RAG-Upload:http://rag.local:8001"
)

for svc in "${SERVICES[@]}"; do
  name="${svc%%:*}"
  url="${svc#*:}"
  echo -n "🔍 $name erreichbar? $url ... "
  if docker exec tester curl -fs --max-time 5 "$url" > /dev/null; then
    echo "✅ Ja"
  else
    echo "❌ Nein"
  fi
done

echo "🎉 Setup abgeschlossen. Bitte trage folgende Einträge in die DNS- oder /etc/hosts-Datei deiner Clients ein:"
echo " - [IP-Host]  chat.local n8n.local whisper.local ollama.local"
echo "Dann im Browser öffnen:"
echo " - http://chat.local         (Open WebUI)"
echo " - http://n8n.local          (n8n Workflowsystem)"
echo " - http://whisper.local/docs (Whisper API UI)"
echo " - http://ollama.local       (Ollama API direkt)"
echo " - http://rag.local       (Ollama API direkt)"
echo " - http://<Server-IP>         (Caddy selbst, optional)"
