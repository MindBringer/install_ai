from fastapi import FastAPI
from pydantic import BaseModel
from crew import init_crew

app = FastAPI()

class CrewQuery(BaseModel):
    question: str

@app.post("/ask")
def ask_crew(q: CrewQuery):
    crew = init_crew(q.question)
    result = crew.kickoff()
    return {"answer": result}
