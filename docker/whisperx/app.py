import os
import tempfile
import shutil
from pathlib import Path
from fastapi import FastAPI, UploadFile, File, HTTPException
from pydantic import BaseModel
import torch # Import für torch.cuda.is_available()

# Import von whisperx könnte je nach Installation direkt funktionieren,
# oder Sie müssen es innerhalb der Funktion importieren, wenn es zu Abhängigkeitskonflikten führt.
import whisperx
import gc # Garbage Collection für Modell-Bereinigung

app = FastAPI(title="WhisperX API",
              description="API for audio transcription and diarization using WhisperX")

# Modell- und Gerätekonfiguration
# Diese Werte könnten auch über Umgebungsvariablen gesteuert werden
BATCH_SIZE = 16 # Reduce if you run out of memory
# device = "cuda" if torch.cuda.is_available() else "cpu" # Wäre für GPU-Unterstützung
device = "cpu" # Für dieses Setup bleiben wir bei CPU
compute_type = "int8" # for CPU, "float16" for GPU

# Globales Modell-Caching, um das Modell nicht bei jeder Anfrage neu zu laden
# Initialisiere auf None, lade bei erster Anfrage
audio_model = None
diarize_model = None

# Helper function to load models
def load_whisperx_models(lang: str = "de"):
    global audio_model, diarize_model
    if audio_model is None:
        print(f"Loading WhisperX audio model for language: {lang} on {device} with compute_type: {compute_type}...")
        audio_model = whisperx.load_model("large-v2", device, compute_type=compute_type, language=lang)
    if diarize_model is None:
        print("Loading WhisperX diarization model...")
        diarize_model = whisperx.DiarizationPipeline(use_auth_token=os.getenv("HF_TOKEN")) # Verwendet HF_TOKEN

# Pydantic Model für Transkriptions-Antwort
class TranscriptionResult(BaseModel):
    status: str
    diarized: bool
    result: dict # Das komplette JSON-Ergebnis von WhisperX

@app.on_event("startup")
async def startup_event():
    # Optional: Modelle beim Start laden, wenn genügend RAM/VRAM vorhanden ist
    # load_whisperx_models()
    print("WhisperX API started. Models will be loaded on first request.")

@app.post("/transcribe", response_model=TranscriptionResult)
async def transcribe_audio(file: UploadFile = File(...), lang: str = "de"):
    """
    Transcribes an audio file using WhisperX, with optional diarization.
    """
    # Temporäre Datei speichern
    with tempfile.NamedTemporaryFile(delete=False, suffix=f".{file.filename.split('.')[-1]}") as tmp_file:
        shutil.copyfileobj(file.file, tmp_file)
        audio_path = tmp_file.name

    try:
        # Modelle laden (oder verwenden die bereits geladenen globalen Modelle)
        load_whisperx_models(lang=lang)

        # 1. Transkription
        audio = whisperx.load_audio(audio_path)
        result = audio_model.transcribe(audio, batch_size=BATCH_SIZE)

        # 2. Alignment (Spracherkennung)
        model_a, metadata = whisperx.load_align_model(language_code=result["language"], device=device)
        aligned_result = whisperx.align(result["segments"], model_a, audio, device, return_char_alignments=False)

        # 3. Diarization (Sprechererkennung)
        diarized_segments = None
        if diarize_model is not None: # Sicherstellen, dass das Modell geladen ist
            diarize_segments = diarize_model(audio, aligned_result["segments"])
            # Führt Diarization-Ergebnisse mit transkribierten Segmenten zusammen
            diarized_segments = whisperx.assign_word_speakers(diarize_segments, aligned_result["segments"])

        # Aufräumen: Modelle entladen und Cache leeren, um Speicher freizugeben
        # Dies ist besonders wichtig bei CPU-Nutzung oder wenn viele Modelle im Einsatz sind
        # Wenn Sie die Modelle im Speicher halten wollen (z.B. für schnellere Folgeanfragen),
        # entfernen Sie diese Zeilen oder passen Sie die Logik an.
        # del model_a
        # gc.collect()
        # torch.cuda.empty_cache() # Nur für GPU

        return {
            "status": "success",
            "diarized": True if diarized_segments else False,
            "result": diarized_segments if diarized_segments else aligned_result
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")
    finally:
        # Temporäre Datei löschen
        os.unlink(audio_path)
        # Überlegen Sie, ob Sie hier auch die Modelle entladen wollen, um RAM freizugeben.
        # Wenn Sie die Modelle dauerhaft im Speicher behalten wollen für schnellere Folgeanfragen,
        # dann kommentieren Sie die folgenden Zeilen aus:
        # global audio_model, diarize_model
        # del audio_model
        # del diarize_model
        # audio_model = None
        # diarize_model = None
        # gc.collect()
        # if torch.cuda.is_available():
        #    torch.cuda.empty_cache()