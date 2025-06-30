from fastapi import FastAPI, Depends, HTTPException, Request
from auth_middleware import get_user_context
from qdrant_client import QdrantClient
from qdrant_client.http.models import Filter, FieldCondition, MatchAny, SearchParams
import httpx, os

app = FastAPI()

QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
OLLAMA_URL  = os.getenv("OLLAMA_URL", "http://ollama:11434")
client = QdrantClient(url=QDRANT_URL)

@app.get("/search")
async def search(query: str, user=Depends(get_user_context)):
    user_groups = user.get("groups", [])

    # Schritt 1: Hole Embedding des Queries
    async with httpx.AsyncClient() as http:
        resp = await http.post(f"{OLLAMA_URL}/api/embeddings", json={
            "model": "nomic-embed-text",
            "prompt": query
        })
        if resp.status_code != 200:
            raise HTTPException(500, detail="Embedding failed")
        vector = resp.json().get("embedding")

    # Schritt 2: Qdrant-Suche mit Filter nach Gruppe/public
    group_filter = Filter(
        should=[
            FieldCondition(key="access", match=MatchAny(any=["public"])),
            FieldCondition(key="group", match=MatchAny(any=user_groups))
        ]
    )
    results = client.search(
        collection_name="docs",
        query_vector=vector,
        query_filter=group_filter,
        limit=5,
        search_params=SearchParams(hnsw_ef=64)
    )

    context = "\n---\n".join([hit.payload["text"] for hit in results if hit.payload and "text" in hit.payload])

    # Schritt 3: Frage an Ollama LLM stellen
    prompt = f"Beantworte die folgende Frage auf Basis der Dokumente:\n{context}\n\nFrage: {query}"

    async with httpx.AsyncClient() as http:
        r = await http.post(f"{OLLAMA_URL}/api/generate", json={
            "model": "mistral",
            "prompt": prompt,
            "stream": False
        })
        if r.status_code != 200:
            raise HTTPException(500, detail="LLM failed")
        answer = r.json().get("response")

    return {"question": query, "answer": answer, "hits": len(results)}