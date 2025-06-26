# KI-Stack Setup mit Whisper, n8n, Doc-Parser und Ollama (Headless Ubuntu 24.04)

Diese Anleitung beschreibt die vollständige Einrichtung eines lokalen KI-Stacks auf einem **Ubuntu 24.04 LTS Headless-Server** – inklusive Firewall, Docker, Whisper-Spracherkennung und Mistral-Modellzugriff über WebUI und n8n.

---

## 🖥️ 1. Vorbereitung: Ubuntu Server (Headless) Installation

### Voraussetzungen:
- Ubuntu 24.04 LTS (ohne GUI)
- Netzwerkzugang (DHCP oder statisch)
- Tastatur und Bildschirm oder serieller Zugriff

### Wichtig:
- Während der Grundinstallation gerne SSH aktivieren, Docker kann mit installiert werden.
- Benutzer mit `sudo`-Rechten einrichten (z. B. `admin`)
- Zeitzone, Hostname und Partitionierung nach Bedarf

---

## 🧰 2. Setup vorbereiten: Git + USB-Stick

### Auf deinem lokalen Rechner (z. B. MacBook):

1. Lade das vorbereitete Git-Repository oder ZIP-Paket von GitHub herunter.
2. Kopiere den kompletten Ordner (inkl. `ki-setup.sh`, Token-Datei etc.) auf einen **USB-Stick (FAT32 oder ext4)**.

---

## 🖴 3. Setup auf dem Ubuntu-Server starten

### USB-Stick mounten (Beispiel):

```bash
sudo mkdir /mnt/usb
sudo mount /dev/sda1 /mnt/usb
```

> Ersetze `sda1` durch den korrekten Gerätenamen (`lsblk` hilft).

### Git installieren:

```bash
sudo apt update
sudo apt install git -y
```

Falls Git-Zugriffstoken vorhanden:

### Repository clonen (z. B. dein GitHub-Repo):

```bash
git clone https://token@github.com/MindBringer/ai-server-setup.git /home/user/ai-server-setup
```

Oder kopiere einfach alle Skripte von USB auf den Server:

```bash
sudo cp -r /mnt/usb/* /home/USER/ai-server-setup
cd /home/USER/ai-server-setup
chmod +x *.sh
```

---

## 🤖 5. KI-Stack installieren

### Setup starten:

```bash
bash ./ki-setup.sh
```

### Dieses Skript:

- prüft Docker & startet es
- installiert Ollama inkl. `mistral` & `whisper`
- schreibt eine `docker-compose.yml` nach `/home/USER/ai-stack`
- startet alle Container:
  - 🧠 `ollama` (KI-Modelle)
  - 💬 `webui` (grafisches Frontend für Chat / Datei)
  - 🗂️ `qdrant` (Vektordatenbank)
  - 🛠️ `n8n` (Automation / Workflows)

### für Web-RAG über n8n (broken in V1.99.1):
mv rag_ui_frontend.html ~/ai-stack/public/rag.html
