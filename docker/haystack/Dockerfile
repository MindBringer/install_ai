FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./

# Installiere Systemtools nur für PDF / docx
RUN apt-get update && apt-get install -y libmagic1 poppler-utils && \
    pip install --no-cache-dir -r requirements.txt

COPY . /app

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8001"]

