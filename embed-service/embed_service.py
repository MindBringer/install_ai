from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer

app = FastAPI()
model = SentenceTransformer("all-MiniLM-L6-v2")

class EmbedRequest(BaseModel):
    input: list[str]

class EmbedResponse(BaseModel):
    embeddings: list[list[float]]

@app.post("/embed", response_model=EmbedResponse)
async def embed(req: EmbedRequest):
    try:
        vectors = model.encode(req.input, show_progress_bar=False)
        return {"embeddings": vectors.tolist()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
print("REQ JSON:", await request.json())
