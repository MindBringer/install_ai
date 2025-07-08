
#!/bin/bash
set -euo pipefail

echo "🧪 Starte Frontend-Test: lokal & LAN-Verfügbarkeit"

HOSTNAME="api.local"
LOCAL_URL="http://localhost:8001/query"
HTTPS_URL="https://api.local/query"
CURL_OPTS="--silent --show-error --fail --max-time 5"

echo ""
echo "🔹 1. Teste lokale API über localhost (unverschlüsselt)"
echo "   ➤ $LOCAL_URL"
if response=$(curl $CURL_OPTS -X POST "$LOCAL_URL" -H "Content-Type: application/json" -d '{"prompt":"ping"}' 2>&1); then
  echo "✅ Lokal (http://localhost:8001) OK"
else
  echo "❌ Lokal (http://localhost:8001) FEHLER:"
  echo "$response"
fi

echo ""
echo "🔹 2. Teste API über LAN via TLS und api.local (Caddy Reverse Proxy)"
echo "   ➤ $HTTPS_URL"
if response=$(curl $CURL_OPTS -X POST "$HTTPS_URL" -H "Content-Type: application/json" -d '{"prompt":"ping"}' --insecure 2>&1); then
  echo "✅ LAN (https://api.local) OK"
else
  echo "❌ LAN (https://api.local) FEHLER:"
  echo "$response"
fi

echo ""
echo "🔹 3. DNS & /etc/hosts Prüfung"
if getent hosts "$HOSTNAME" > /dev/null; then
  ip=$(getent hosts "$HOSTNAME" | awk '{ print $1 }')
  echo "✅ DNS-/Hosts-Auflösung für $HOSTNAME → $ip"
else
  echo "❌ Kann $HOSTNAME nicht auflösen. /etc/hosts Eintrag fehlt?"
fi

echo ""
echo "🔹 4. CORS-Test (Frontend)"
FRONTEND_JS=$(grep -i 'VITE_API_BASE_URL' $HOME/ai-stack/.env || echo "VITE_API_BASE_URL NICHT GEFUNDEN")
echo "📦 .env Eintrag: $FRONTEND_JS"

echo ""
echo "✅ Test abgeschlossen."
echo "🔁 Bitte kopiere die gesamte Ausgabe und sende sie weiter zur Analyse."
