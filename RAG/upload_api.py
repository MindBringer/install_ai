
import os
import io
import uuid
import logging
from fastapi import FastAPI, UploadFile, File, HTTPException
import httpx
from pypdf import PdfReader
import docx
import html2text
from pdf2image import convert_from_bytes
import pytesseract
import pypandoc
import pandas as pd
from qdrant_client import QdrantClient
import hashlib
from qdrant_client.http.models import Filter, FieldCondition, MatchValue, Distance, VectorParams
import tiktoken

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
EMBEDDING_ENDPOINT = os.getenv("EMBEDDING_URL")
EMBEDDING_API_KEY = os.getenv("EMBEDDING_API_KEY")

ENCODING = tiktoken.get_encoding("gpt2")
MAX_TOKENS = 500
OVERLAP    = 50

def chunk_text(text: str) -> list[str]:
    token_ids = ENCODING.encode(text)
    chunks = []
    i = 0
    total = len(token_ids)
    while i < total:
        window = token_ids[i : i + MAX_TOKENS]
        chunks.append(ENCODING.decode(window))
        i += MAX_TOKENS - OVERLAP
    return chunks

app = FastAPI()
client = QdrantClient(url=QDRANT_URL)

def parse_pdf(contents: bytes) -> str:
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

def parse_docx(contents: bytes) -> str:
    document = docx.Document(io.BytesIO(contents))
    return "\n".join(p.text for p in document.paragraphs)

def parse_html(contents: bytes) -> str:
    return html2text.html2text(contents.decode("utf-8", errors="ignore"))

def parse_rtf(contents: bytes) -> str:
    try:
        return pypandoc.convert_text(contents.decode('utf-8', errors='ignore'), 'plain', format='rtf')
    except Exception as e:
        logger.warning(f"RTF conversion failed, falling back to plain decode: {e}")
        return contents.decode('utf-8', errors='ignore')

def parse_odt(contents: bytes) -> str:
    try:
        return pypandoc.convert_text(contents.decode('utf-8', errors='ignore'), 'plain', format='odt')
    except Exception as e:
        logger.warning(f"ODT conversion failed, falling back to plain decode: {e}")
        return contents.decode('utf-8', errors='ignore')

def parse_csv(contents: bytes) -> str:
    try:
        df = pd.read_csv(io.BytesIO(contents), sep=None, engine='python')
    except Exception as e:
        logger.warning(f"CSV parse failed: {e}")
        df = pd.read_csv(io.BytesIO(contents))
    return df.to_string(index=False)

def parse_xlsx(contents: bytes) -> str:
    try:
        sheets = pd.read_excel(io.BytesIO(contents), sheet_name=None)
        texts = []
        for name, df in sheets.items():
            texts.append(f"Sheet: {name}")
            texts.append(df.to_string(index=False))
        return "\n\n".join(texts)
    except Exception as e:
        logger.error(f"Excel parse failed: {e}")
        raise

def parse_text(contents: bytes) -> str:
    return contents.decode("utf-8", errors="ignore")

@app.post("/upload")
async def upload(file: UploadFile = File(...)):
    filename = file.filename
    ext = os.path.splitext(filename)[1].lower()

    contents = await file.read()
    try:
        if ext == ".pdf":
            text = parse_pdf(contents)
        elif ext == ".docx":
            text = parse_docx(contents)
        elif ext in {".html", ".htm"}:
            text = parse_html(contents)
        elif ext == ".rtf":
            text = parse_rtf(contents)
        elif ext == ".odt":
            text = parse_odt(contents)
        elif ext in {".csv", ".tsv"}:
            text = parse_csv(contents)
        elif ext in {".xlsx", ".xls"}:
            text = parse_xlsx(contents)
        elif filename.endswith(".txt"):
            try:
                text = contents.decode("utf-8")
            except UnicodeDecodeError:
                text = contents.decode("latin-1")
        else:
            text = parse_text(contents)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error parsing {filename}: {e}")
        raise HTTPException(status_code=400, detail="Failed to parse document")

    if not text.strip():
        raise HTTPException(status_code=400, detail="No text extracted from document")

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

            try:
                response = await http.post(
                    EMBEDDING_ENDPOINT,
                    json={"input": [chunk]},
                    headers={"Authorization": f"Bearer {EMBEDDING_API_KEY}"} if EMBEDDING_API_KEY else None
                )
                response.raise_for_status()
                embedding = response.json().get("embeddings")[0]
            except Exception as e:
                logger.error(f"Embedding request failed: {e}")
                raise HTTPException(status_code=500, detail="Embedding generation failed")

            point_id = str(uuid.uuid4())
            points.append({
                "id": point_id,
                "vector": embedding,
                "payload": {"text": chunk, "source": filename, "text_hash": text_hash}
            })

    if "docs" not in [col.name for col in client.get_collections().collections]:
        client.create_collection(
            collection_name="docs",
            vectors_config=VectorParams(size=len(embedding), distance=Distance.COSINE),
        )

    try:
        client.upsert(collection_name="docs", points=points)
    except Exception as e:
        logger.error(f"Error upserting into Qdrant: {e}")
        raise HTTPException(status_code=500, detail="Failed to store embeddings")

    return {"success": True, "chunks": len(points), "ids": [p["id"] for p in points]}
