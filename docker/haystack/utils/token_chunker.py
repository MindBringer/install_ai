import tiktoken
from typing import List, Dict

def tokenize(text: str, model: str = 'gpt2') -> List[int]:
    enc = tiktoken.get_encoding(model)
    return enc.encode(text)

def detokenize(tokens: List[int], model: str = 'gpt2') -> str:
    enc = tiktoken.get_encoding(model)
    return enc.decode(tokens)

def split_text_by_tokens(text: str, chunk_size: int = 200, overlap: int = 40, model: str = 'gpt2') -> List[Dict]:
    tokens = tokenize(text, model)
    chunks = []
    i = 0
    while i < len(tokens):
        chunk_tokens = tokens[i:i+chunk_size]
        chunk_text = detokenize(chunk_tokens, model)
        chunks.append({
            "content": chunk_text,
            "meta": {"offset_start_tokens": i, "offset_end_tokens": i+len(chunk_tokens)}
        })
        i += chunk_size - overlap
    return chunks
