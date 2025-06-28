import os
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
import httpx
from qdrant_client import QdrantClient
from qdrant_client.http.models import Filter, FieldCondition, MatchValue, MatchAny

app = FastAPI()
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
EMBEDDING_ENDPOINT = os.getenv("EMBEDDING_URL")
client = QdrantClient(url=QDRANT_URL)

@app.get("/search")
async def search(request: Request, query: str):
    user_groups = request.headers.get("X-User-Groups", "")
    user_group_list = [g.strip() for g in user_groups.split(",") if g.strip()]

    access_filter = Filter(
        should=[
            FieldCondition(key="access", match=MatchValue(value="public"))
        ]
    )
    if user_group_list:
        access_filter.should.append(
            FieldCondition(key="group", match_any=MatchAny(any_values=user_group_list))
        )

    async with httpx.AsyncClient() as http:
        response = await http.post(EMBEDDING_ENDPOINT, json={"input": query})
        response.raise_for_status()
        embedding = response.json().get("embeddings")[0]

    results = client.search(
        collection_name="docs",
        query_vector=embedding,
        limit=10,
        search_filter=access_filter
    )

    hits = [
        {
            "id": r.id,
            "score": r.score,
            "text": r.payload.get("text"),
            "source": r.payload.get("source"),
            "access": r.payload.get("access"),
            "group": r.payload.get("group")
        }
        for r in results
    ]

    return JSONResponse(content={"results": hits})