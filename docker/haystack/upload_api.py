from fastapi import FastAPI, UploadFile, File
from haystack.document_stores import QdrantDocumentStore
from haystack.nodes import EmbeddingRetriever, PDFToTextConverter, TextConverter, DocxToTextConverter
from haystack import Document
import os
import shutil
from utils.token_chunker import split_text_by_tokens

app = FastAPI()

UPLOAD_DIR = '/app/uploads'
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Setup Qdrant
document_store = QdrantDocumentStore(
    host=os.getenv("QDRANT_HOST", "qdrant"),
    port=6333,
    embedding_dim=384,
    index="rag-index"
)

# EmbeddingRetriever mit SentenceTransformer oder Ollama (extern konfigurierbar)
retriever = EmbeddingRetriever(
    document_store=document_store,
    embedding_model="sentence-transformers/all-MiniLM-L6-v2",  # oder Ollama-Wrapper
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
