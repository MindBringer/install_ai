from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
from qdrant_haystack.document_stores import QdrantDocumentStore
from haystack.nodes import EmbeddingRetriever, PDFToTextConverter, TextConverter, DocxToTextConverter
from haystack import Document
from utils.token_chunker import split_text_by_tokens
from pathlib import Path
import os, shutil, requests, tempfile
import subprocess
import json

app = FastAPI()

UPLOAD_DIR = "/app/uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

document_store = QdrantDocumentStore(
    host=os.getenv("QDRANT_HOST", "qdrant"),
    port=6333,
    embedding_dim=384,
    index="rag-index"
)

retriever = EmbeddingRetriever(
    document_store=document_store,
    embedding_model="sentence-transformers/all-MiniLM-L6-v2",
    model_format="sentence_transformers"
)

# Konverter
pdf_converter = PDFToTextConverter(remove_numeric_tables=True, valid_languages=["de", "en"])
text_converter = TextConverter(remove_numeric_tables=True, valid_languages=["de", "en"])
docx_converter = DocxToTextConverter(remove_numeric_tables=True, valid_languages=["de", "en"])

def convert_file(file_path: str) -> str:
    ext = file_path.lower().split('.')[-1]
    if ext == "pdf":
        docs = pdf_converter.convert(file_path=file_path, meta={"source": os.path.basename(file_path)})
    elif ext == "docx":
        docs = docx_converter.convert(file_path=file_path, meta={"source": os.path.basename(file_path)})
    elif ext in ["txt", "md", "csv"]:
        docs = text_converter.convert(file_path=file_path, meta={"source": os.path.basename(file_path)})
    else:
        raise ValueError("Unsupported file format")
    return docs[0].content if docs else ""

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    file_path = os.path.join(UPLOAD_DIR, file.filename)
    with open(file_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    try:
        text = convert_file(file_path)
    except Exception as e:
        return {"error": str(e), "filename": file.filename}

    chunks = split_text_by_tokens(text, chunk_size=200, overlap=40)
    documents = [Document(content=chunk['content'], meta={"source": file.filename, **chunk["meta"]}) for chunk in chunks]

    document_store.write_documents(documents)
    document_store.update_embeddings(retriever)

    return {"status": "uploaded", "chunks": len(documents), "filename": file.filename}

class Query(BaseModel):
    question: str
    model: str = "mistral" # Standardmodell ist "mistral"

@app.post("/query")
async def query_question(payload: Query):
    docs = retriever.retrieve(payload.question, top_k=5)
    context = "\n---\n".join([doc.content for doc in docs])
    prompt = f"""Beantworte auf Basis dieser Informationen:
{context}

Frage: {payload.question}
""" # Wichtig: Hier wurde das Prompt-Format korrigiert, es war zuvor nicht korrekt eingerückt.

    # Dynamische Auswahl des Ollama-Hosts basierend auf payload.model
    # Die Servicenamen im Docker-Compose sind z.B. "ollama-mistral", "ollama-mixtral" etc.
    # Wir bilden den Ollama-Hostnamen, indem wir "ollama-" voranstellen.
    ollama_service_name = f"ollama-{payload.model}"
    ollama_url = f"http://{ollama_service_name}:11434/api/generate"

    # Anfrage an Ollama senden
    try:
        res = requests.post(
            ollama_url, # Verwende den dynamisch erzeugten Ollama-URL
            json={"model": payload.model, "prompt": prompt}
        )
        res.raise_for_status() # Löst einen HTTPError für schlechte Antworten (4xx oder 5xx) aus
        llm_answer = res.json().get("response", "")
    except requests.exceptions.RequestException as e:
        # Hier spezifischere Fehlerbehandlung für requests-Fehler
        llm_answer = f"Fehler bei der Kommunikation mit Ollama ({ollama_service_name}): {e}"
    except Exception as e:
        # Allgemeine Fehlerbehandlung
        llm_answer = f"Ollama-Fehler: {e}"

    return {
        "answer": llm_answer,
        "sources": [{"file": doc.meta.get("source", ""), "tokens": f"{doc.meta.get('offset_start_tokens')}–{doc.meta.get('offset_end_tokens')}"} for doc in docs]
    }

@app.post("/crew/ask")
async def crew_ask(q: Query):
    try:
        r = requests.post("http://crewai:8010/ask", json={"question": q.question})
        return r.json()
    except Exception as e:
        return {"error": f"CrewAI nicht erreichbar: {e}"}

@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...), lang: str = "de"):
    """
    Transcribes an audio file by sending it to the WhisperX API service.
    """
    # Temporäre Datei speichern (nicht mehr nötig, wenn direkt an WhisperX API gesendet wird)
    # Stattdessen direkt die Datei an den WhisperX-Dienst streamen
    
    # URL des WhisperX-Dienstes im Docker-Netzwerk
    # Da der Dienst 'whisperx' heißt und Port 8080 exponiert, ist dies die interne URL
    WHISPERX_API_URL = "http://whisperx:8080/transcribe"

    try:
        # Sende die Audiodatei als Multipart-Form-Data an den WhisperX-Dienst
        files = {'file': (file.filename, file.file, file.content_type)}
        params = {'lang': lang} # Sprachparameter übergeben

        # Timeout für die Anfrage, da Transkription lange dauern kann
        response = requests.post(WHISPERX_API_URL, files=files, params=params, timeout=600) # 10 Minuten Timeout
        response.raise_for_status() # Löst HTTPError für 4xx/5xx Antworten aus

        result = response.json()
        return result

    except requests.exceptions.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Fehler bei der Kommunikation mit WhisperX API: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transkriptionsanfrage fehlgeschlagen: {e}")
