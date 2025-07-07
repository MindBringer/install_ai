FROM python:3.10-slim

WORKDIR /app

# Installiere System-Abhängigkeiten
RUN apt-get update && apt-get install -y ffmpeg git git-lfs && \
    rm -rf /var/lib/apt/lists/* # Cleanup APT cache

# Kopiere die requirements.txt und installiere Python-Abhängigkeiten
# Dies sollte VOR dem Kopieren des Anwendungs-Codes geschehen, um Layer-Caching zu optimieren
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir git+https://github.com/m-bain/whisperx

# Kopiere den Anwendungscode
COPY . /app

# Überprüfe die Installation (optional, kann entfernt werden)
RUN git lfs install && \
    python3 -m whisperx --help || true

# Starte die FastAPI-Anwendung mit Uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
