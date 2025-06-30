from fastapi import FastAPI, UploadFile, File, HTTPException, Header
from fastapi.responses import JSONResponse
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams, Filter, FieldCondition, MatchValue
import httpx
import uuid
import os
import hashlib
import shutil
import tempfile
import logging

app = FastAPI()

QDRANT_URL = os.getenv("QDRANT_URL", "http://localhost:6333")
WHISPER_URL = os.getenv("WHISPER_URL", "http://whisper:9000/transcribe")
EMBEDDING_URL = os.getenv("EMBEDDING_URL", "http://embedding:8000/embed")
EMBEDDING_API_KEY = os.getenv("EMBEDDING_API_KEY")
COLLECTION_NAME = "docs"

client = QdrantClient(url=QDRANT_URL)
logging.basicConfig(level=logging.INFO)

@app.post("/upload-audio")
async def upload_audio(
    file: UploadFile = File(...),
    access: str = "public",
    group: str = "",
    authorization: str = Header(None)
):
    if not file.filename.lower().endswith(('.mp3', '.wav', '.m4a', '.ogg', '.flac')):
        raise HTTPException(status_code=400, detail="Unsupported audio format")

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = tmp.name

    # Call Whisper transcription API
    try:
        async with httpx.AsyncClient(timeout=300.0) as http:
            with open(tmp_path, "rb") as audio_file:
                files = {'file': (file.filename, audio_file, file.content_type)}
                headers = {"Authorization": f"Bearer {authorization}"} if authorization else {}
                whisper_response = await http.post(WHISPER_URL, files=files, headers=headers)
                whisper_response.raise_for_status()
                transcript_json = whisper_response.json()
                full_text = transcript_json.get("text", "")
                segments = transcript_json.get("segments", [])
    except Exception as e:
        logging.error(f"Whisper transcription failed: {e}")
        raise HTTPException(status_code=500, detail="Transcription failed")
    finally:
        os.remove(tmp_path)

    if not full_text.strip():
        raise HTTPException(status_code=400, detail="Empty transcription")

    # Chunking & Embedding
    chunks = [full_text]  # optionally add chunking by timestamps
    points = []
    async with httpx.AsyncClient() as http:
        for chunk in chunks:
            text_hash = hashlib.sha256(chunk.encode("utf-8")).hexdigest()
            duplicate = client.scroll(
                collection_name=COLLECTION_NAME,
                scroll_filter=Filter(must=[FieldCondition(key="text_hash", match=MatchValue(value=text_hash))]),
                limit=1
            )
            if duplicate and duplicate[0]:
                logging.info("Duplicate detected — skipping.")
                continue

            try:
                response = await http.post(
                    EMBEDDING_URL,
                    json={"input": chunk},
                    headers={"Authorization": f"Bearer {EMBEDDING_API_KEY}"} if EMBEDDING_API_KEY else {}
                )
                response.raise_for_status()
                embedding = response.json().get("embeddings")[0]
            except Exception as e:
                logging.error(f"Embedding request failed: {e}")
                raise HTTPException(status_code=500, detail="Embedding generation failed")

            points.append({
                "id": str(uuid.uuid4()),
                "vector": embedding,
                "payload": {
                    "text": chunk,
                    "source": file.filename,
                    "access": access,
                    "group": group if access == "restricted" else "",
                    "text_hash": text_hash,
                    "type": "audio",
                    "metadata": segments  # includes speaker, timestamps, etc.
                }
            })

    if COLLECTION_NAME not in [c.name for c in client.get_collections().collections]:
        client.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=VectorParams(size=len(points[0]["vector"]), distance=Distance.COSINE),
        )

    try:
        client.upsert(collection_name=COLLECTION_NAME, points=points)
    except Exception as e:
        logging.error(f"Upsert into Qdrant failed: {e}")
        raise HTTPException(status_code=500, detail="Failed to store embeddings")

    return JSONResponse(content={"success": True, "chunks": len(points), "transcription": full_text, "metadata": segments})