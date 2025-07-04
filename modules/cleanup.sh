#!/bin/bash
set -e

echo "🧼 Bereinige /var/lib/docker ..."

sudo systemctl stop docker

if [ -d /var/lib/docker ]; then
    echo "🔍 Inhalt gefunden – lösche..."
    sudo rm -rf /var/lib/docker
    sudo mkdir /var/lib/docker
    sudo chown root:root /var/lib/docker
    sudo chmod 755 /var/lib/docker
    echo "✅ /var/lib/docker wurde bereinigt."
else
    echo "ℹ️ /var/lib/docker existiert nicht oder wurde bereits gelöscht."
fi

sudo systemctl start docker