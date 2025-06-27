import os
import httpx
from fastapi import FastAPI, HTTPException, Query
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams
import uuid

app = FastAPI()

QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
EMBEDDING_URL = os.getenv("EMBEDDING_URL", "http://embedding:8000/embed")
EMBEDDING_API_KEY = os.getenv("EMBEDDING_API_KEY")

client = QdrantClient(QDRANT_URL)

@app.get("/search")
async def search(q: str = Query(..., description="Text query to search for similar documents")):
    # Hole Embedding für Anfrage
    try:
        async with httpx.AsyncClient() as http:
            response = await http.post(
                EMBEDDING_URL,
                json={"input": [q]},
                headers={"Authorization": f"Bearer {EMBEDDING_API_KEY}"} if EMBEDDING_API_KEY else None
            )
            response.raise_for_status()
            embedding = response.json().get("embeddings")[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Embedding failed: {e}")

    # Suche in Qdrant
    try:
        results = client.search(
            collection_name="docs",
            query_vector=embedding,
            limit=5
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Qdrant search failed: {e}")

    return [{"score": r.score, "text": r.payload.get("text", "")} for r in results]
