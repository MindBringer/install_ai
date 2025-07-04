FROM python:3.11-slim

# System‐Deps falls nötig (z.B. für tokenizers, sentence-transformers)
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements-embed.txt ./
RUN pip install --no-cache-dir -r requirements-embed.txt

COPY embed_service.py ./

EXPOSE 8000
CMD ["uvicorn", "embed_service:app", "--host", "0.0.0.0", "--port", "8000"]
