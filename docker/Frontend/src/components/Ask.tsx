import React, { useState } from 'react'
import { askQuestion } from '../lib/api'

interface Props {
  selectedModel: string
}

export default function Ask({ selectedModel }: Props) {
  const [question, setQuestion] = useState('')
  const [answer, setAnswer] = useState('')
  const [crewAnswer, setCrewAnswer] = useState('')
  const [loading, setLoading] = useState(false)

  const handleAsk = async () => {
    if (!question) return
    setAnswer('')
    setCrewAnswer('')
    setLoading(true)
    try {
      const response = await askQuestion(question, selectedModel)
      setAnswer(response.answer || JSON.stringify(response))
    } catch (error) {
      setAnswer('Fehler bei Anfrage')
    }
    setLoading(false)
  }

  const handleCrewAI = async () => {
    setCrewAnswer('CrewAI denkt...')
    try {
      const response = await fetch('http://localhost:8010/crew/ask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question })
      })
      const result = await response.json()
      setCrewAnswer(result.answer || JSON.stringify(result))
    } catch (e) {
      setCrewAnswer('Fehler bei CrewAI-Anfrage')
    }
  }

  return (
    <div className="space-y-2 border p-4 rounded-xl">
      <input
        type="text"
        value={question}
        onChange={(e) => setQuestion(e.target.value)}
        placeholder="Frage eingeben"
        className="border p-2 w-full"
      />
      <div className="flex gap-2">
        <button onClick={handleAsk} className="bg-green-500 text-white px-4 py-2 rounded">
          Direkt fragen
        </button>
        <button onClick={handleCrewAI} className="bg-purple-600 text-white px-4 py-2 rounded">
          CrewAI fragen
        </button>
      </div>
      {loading && <div className="text-gray-400">Wird verarbeitet…</div>}
      {answer && <div className="text-sm text-gray-800 whitespace-pre-wrap">Antwort: {answer}</div>}
      {crewAnswer && <div className="text-sm text-gray-700 whitespace-pre-wrap">CrewAI: {crewAnswer}</div>}
    </div>
  )
}
