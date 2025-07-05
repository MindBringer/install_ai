from crewai import Task

def create_tasks(question: str):
    return [
        Task(description=f"Analysiere die folgende Nutzerfrage: '{question}'", expected_output="Strukturierte Analyse"),
        Task(description="Formuliere eine verständliche Antwort", expected_output="Lesbare, fundierte Antwort"),
        Task(description="Bewerte die Qualität der Antwort", expected_output="Kritische Rückmeldung und finale Fassung")
    ]
