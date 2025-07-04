import React, { useState } from 'react'
import { uploadFile } from '../lib/api'

export default function Upload() {
  const [file, setFile] = useState<File | null>(null)
  const [status, setStatus] = useState('')

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      setFile(e.target.files[0])
    }
  }

  const handleUpload = async () => {
    if (!file) return
    setStatus('Uploading...')
    try {
      const response = await uploadFile(file)
      setStatus('Upload successful: ' + JSON.stringify(response))
    } catch (error) {
      setStatus('Upload failed')
    }
  }

  return (
    <div className="space-y-2 border p-4 rounded-xl">
      <input type="file" onChange={handleChange} />
      <button onClick={handleUpload} className="bg-blue-500 text-white px-4 py-2 rounded">
        Datei hochladen
      </button>
      <div className="text-sm text-gray-600">{status}</div>
    </div>
  )
}
