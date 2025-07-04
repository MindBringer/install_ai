FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    tesseract-ocr \
    poppler-utils \
    unrtf \
    pandoc \
    curl \
    libmagic1 && rm -rf /var/lib/apt/lists/*
    
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements-upload.txt

COPY upload_api.py ./

CMD ["uvicorn", "upload_api:app", "--host", "0.0.0.0", "--port", "8001"]