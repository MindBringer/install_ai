import axios from 'axios'

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8001'

export async function uploadFile(file: File) {
  const formData = new FormData()
  formData.append('file', file)

  const response = await axios.post(`${API_BASE}/upload`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  })

  return response.data
}

export async function askQuestion(question: string, model: string = 'mistral') {
  const response = await axios.post(`${API_BASE}/query`, {
    question,
    model
  })

  return response.data
}

export async function listModels() {
  const response = await axios.get(`${API_BASE}/models`)
  return response.data
}
