from crewai import Agent

analyst = Agent(
    role="Analyst",
    goal="Analysiere Informationen zur gestellten Frage",
    backstory="Du bist ein sachlicher Datenanalyst mit Zugriff auf relevante Texte.",
    allow_delegation=False
)

writer = Agent(
    role="Texter",
    goal="Formuliere die Analyse als klare Antwort für den Nutzer",
    backstory="Du bist ein KI-Textgenerator mit dem Ziel, verständliche Texte zu liefern.",
    allow_delegation=False
)

reviewer = Agent(
    role="Prüfer",
    goal="Überprüfe Inhalt und Stil der Antwort",
    backstory="Du bist ein kritischer KI-Lektor, der die Antwort validiert.",
    allow_delegation=False
)
