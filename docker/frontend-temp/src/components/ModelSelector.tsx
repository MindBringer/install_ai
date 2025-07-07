import React, { useEffect, useState } from 'react'
import { listModels } from '../lib/api'

interface Props {
  selectedModel: string
  setSelectedModel: (model: string) => void
}

export default function ModelSelector({ selectedModel, setSelectedModel }: Props) {
  const [models, setModels] = useState<string[]>([])

  useEffect(() => {
    listModels().then((res) => setModels(res.models || [])).catch(() => setModels(['mistral']))
  }, [])

  return (
    <div>
      <label className="block text-sm mb-1">Modell wählen:</label>
      <select
        value={selectedModel}
        onChange={(e) => setSelectedModel(e.target.value)}
        className="border p-2 rounded w-full"
      >
        {models.map((model) => (
          <option key={model} value={model}>
            {model}
          </option>
        ))}
      </select>
    </div>
  )
}
