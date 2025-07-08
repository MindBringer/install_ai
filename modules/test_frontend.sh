#!/bin/bash
set -euo pipefail

echo "🧪 Starte Frontend-Test: lokal & LAN-Verfügbarkeit"
echo ""

# 1. Teste lokale API (unverschlüsselt)
echo "🔹 1. Teste lokale API über localhost (unverschlüsselt)"
echo "   ➤ http://localhost:8001/query"
status_local=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d '{"prompt": "ping"}' http://localhost:8001/query || echo "000")
if [[ "$status_local" == "200" ]]; then
  echo "✅ Lokal (http://localhost:8001) OK (Status 200)"
else
  echo "❌ Lokal (http://localhost:8001) FEHLER:"
  echo "   HTTP-Status: $status_local"
fi
echo ""

# 2. Teste API über LAN / TLS
echo "🔹 2. Teste API über LAN via TLS und api.local (Caddy Reverse Proxy)"
echo "   ➤ https://api.local/query"
status_tls=$(curl -sk -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d '{"prompt": "ping"}' https://api.local/query || echo "000")
if [[ "$status_tls" == "200" ]]; then
  echo "✅ LAN (https://api.local) OK (Status 200)"
else
  echo "❌ LAN (https://api.local) FEHLER:"
  echo "   HTTP-Status: $status_tls"
fi
echo ""

# 3. /etc/hosts oder DNS Prüfung
echo "🔹 3. DNS & /etc/hosts Prüfung"
ip=$(getent hosts api.local | awk '{ print $1 }' || echo "nicht gefunden")
if [[ "$ip" == "127.0.0.1" ]]; then
  echo "✅ DNS-/Hosts-Auflösung für api.local → $ip"
else
  echo "❌ api.local zeigt auf '$ip' – bitte /etc/hosts oder DNS prüfen"
fi
echo ""

# 4. CORS / .env Prüfung
echo "🔹 4. CORS-Test (Frontend)"
PROJECT_DIR="$HOME/ai-stack"
env_path="/$PROJECT_DIR/.env"
if [[ -f "$env_path" ]]; then
  api_env=$(grep VITE_API_BASE_URL "$env_path" | cut -d= -f2-)
  echo "📦 .env Eintrag: VITE_API_BASE_URL=$api_env"
else
  echo "❌ .env Datei nicht gefunden unter $env_path"
fi
echo ""

echo "✅ Test abgeschlossen."
echo "🔁 Bitte kopiere die gesamte Ausgabe und sende sie weiter zur Analyse."
