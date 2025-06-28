import os
import io
import uuid
import logging
import hashlib
from fastapi import FastAPI, UploadFile, File, HTTPException, Request
import httpx
from pypdf import PdfReader
import docx
import html2text
from pdf2image import convert_from_bytes
import pytesseract
import pypandoc
import pandas as pd
from qdrant_client import QdrantClient
from qdrant_client.http.models import Filter, FieldCondition, MatchValue, Distance, VectorParams
import tiktoken

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
EMBEDDING_ENDPOINT = os.getenv("EMBEDDING_URL")
EMBEDDING_API_KEY = os.getenv("EMBEDDING_API_KEY")
ENCODING = tiktoken.get_encoding("gpt2")
MAX_TOKENS = 500
OVERLAP = 50

def chunk_text(text: str) -> list[str]:
    token_ids = ENCODING.encode(text)
    chunks = []
    i = 0
    while i < len(token_ids):
        window = token_ids[i : i + MAX_TOKENS]
        chunks.append(ENCODING.decode(window))
        i += MAX_TOKENS - OVERLAP
    return chunks

app = FastAPI()
client = QdrantClient(url=QDRANT_URL)

def parse_texts(contents: bytes, ext: str, filename: str) -> str:
    try:
        if ext == ".pdf":
            reader = PdfReader(io.BytesIO(contents))
            all_text = []
            for page in reader.pages:
                page_text = page.extract_text() or ""
                if not page_text.strip():
                    images = convert_from_bytes(contents)
                    for image in images:
                        page_text += pytesseract.image_to_string(image)
                all_text.append(page_text)
            return "\n".join(all_text)
        elif ext == ".docx":
            document = docx.Document(io.BytesIO(contents))
            return "\n".join(p.text for p in document.paragraphs)
        elif ext in {".html", ".htm"}:
            return html2text.html2text(contents.decode("utf-8", errors="ignore"))
        elif ext == ".rtf":
            return pypandoc.convert_text(contents.decode("utf-8", errors="ignore"), "plain", format="rtf")
        elif ext == ".odt":
            return pypandoc.convert_text(contents.decode("utf-8", errors="ignore"), "plain", format="odt")
        elif ext in {".csv", ".tsv"}:
            try:
                df = pd.read_csv(io.BytesIO(contents), sep=None, engine="python")
            except Exception:
                df = pd.read_csv(io.BytesIO(contents))
            return df.to_string(index=False)
        elif ext in {".xlsx", ".xls"}:
            sheets = pd.read_excel(io.BytesIO(contents), sheet_name=None)
            texts = []
            for name, df in sheets.items():
                texts.append(f"Sheet: {name}")
                texts.append(df.to_string(index=False))
            return "\n\n".join(texts)
        elif filename.endswith(".txt"):
            try:
                return contents.decode("utf-8")
            except UnicodeDecodeError:
                return contents.decode("latin-1")
        return contents.decode("utf-8", errors="ignore")
    except Exception as e:
        logger.error(f"Parsing failed: {e}")
        raise HTTPException(status_code=400, detail="Failed to parse document")

@app.post("/upload")
async def upload(request: Request, file: UploadFile = File(...)):
    access_level = request.headers.get("X-Access", "public")
    group = request.headers.get("X-Group")
    filename = file.filename
    ext = os.path.splitext(filename)[1].lower()
    contents = await file.read()
    text = parse_texts(contents, ext, filename)

    if not text.strip():
        raise HTTPException(status_code=400, detail="No text extracted")

    chunks = chunk_text(text)
    points = []

    async with httpx.AsyncClient() as http:
        for chunk in chunks:
            text_hash = hashlib.sha256(chunk.encode("utf-8")).hexdigest()

            duplicate = client.scroll(
                collection_name="docs",
                scroll_filter=Filter(
                    must=[FieldCondition(key="text_hash", match=MatchValue(value=text_hash))]
                ),
                limit=1
            )
            if duplicate and duplicate[0]:
                logger.info("Duplicate detected — skipping.")
                continue

            response = await http.post(
                EMBEDDING_ENDPOINT,
                json={"input": chunk},
                headers={"Authorization": f"Bearer {EMBEDDING_API_KEY}"}
            )
            response.raise_for_status()
            embedding = response.json().get("embeddings")[0]

            payload = {
                "text": chunk,
                "source": filename,
                "text_hash": text_hash,
                "access": access_level
            }
            if access_level == "restricted":
                if not group:
                    raise HTTPException(status_code=400, detail="Missing group for restricted document")
                payload["group"] = group

            points.append({
                "id": str(uuid.uuid4()),
                "vector": embedding,
                "payload": payload
            })

    if "docs" not in [col.name for col in client.get_collections().collections]:
        client.create_collection(
            collection_name="docs",
            vectors_config=VectorParams(size=len(embedding), distance=Distance.COSINE),
        )

    if points:
        client.upsert(collection_name="docs", points=points)
    else:
        raise HTTPException(status_code=400, detail="All chunks were duplicates")

    return {"success": True, "chunks": len(points), "ids": [p["id"] for p in points]}
