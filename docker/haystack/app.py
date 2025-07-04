from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
from haystack.document_stores import QdrantDocumentStore
from haystack.nodes import EmbeddingRetriever, PDFToTextConverter, TextConverter, DocxToTextConverter
from haystack import Document
from utils.token_chunker import split_text_by_tokens
import os, shutil, requests, tempfile
import subprocess

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
    model: str = "mistral"

@app.post("/query")
async def query_question(payload: Query):
    docs = retriever.retrieve(payload.question, top_k=5)
    context = "\n---\n".join([doc.content for doc in docs])
    prompt = f"Beantworte auf Basis dieser Informationen:
{context}

Frage: {payload.question}"

    # Anfrage an Ollama senden
    try:
        res = requests.post(
            os.getenv("OLLAMA_HOST", "http://ollama:11434") + "/api/generate",
            json={"model": payload.model, "prompt": prompt}
        )
        llm_answer = res.json().get("response", "")
    except Exception as e:
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
async def transcribe_audio(file: UploadFile = File(...)):
    tmp_wav = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
    shutil.copyfileobj(file.file, tmp_wav)
    tmp_wav.close()

    # WhisperX + Diarization (lokal ausführen via CLI)
    cmd = [
        "whisperx",
        tmp_wav.name,
        "--diarize",
        "--hf_token", os.getenv("HF_TOKEN", ""),
        "--output_dir", UPLOAD_DIR,
        "--output_format", "json"
    ]
    try:
        subprocess.run(cmd, check=True)
        json_path = Path(UPLOAD_DIR) / (Path(tmp_wav.name).stem + ".json")
        with open(json_path, "r") as f:
            return {"status": "ok", "diarized": True, "result": f.read()}
    except Exception as e:
        return {"error": str(e)}
