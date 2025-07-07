from crewai import Crew
from agents import analyst, writer, reviewer
from tasks import create_tasks

def init_crew(question: str):
    tasks = create_tasks(question)
    return Crew(
        agents=[analyst, writer, reviewer],
        tasks=tasks,
        verbose=True
    )
