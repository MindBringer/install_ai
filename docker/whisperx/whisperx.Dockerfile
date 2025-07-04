FROM python:3.10-slim

WORKDIR /app

RUN apt-get update && apt-get install -y ffmpeg git git-lfs && \
    pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir git+https://github.com/m-bain/whisperx && \
    git lfs install && \
    python3 -m whisperx --help || true

CMD ["sleep", "infinity"]
