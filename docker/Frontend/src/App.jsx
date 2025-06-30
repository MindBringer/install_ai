import { useEffect, useState } from "react"
import { PublicClientApplication } from "@azure/msal-browser"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent } from "@/components/ui/card"

const msalConfig = {
  auth: {
    clientId: import.meta.env.VITE_AZURE_CLIENT_ID,
    authority: `https://login.microsoftonline.com/${import.meta.env.VITE_AZURE_TENANT_ID}`,
    redirectUri: window.location.origin,
  },
}

const msalInstance = new PublicClientApplication(msalConfig)

const API_BASE = import.meta.env.VITE_API_BASE_URL || ""

export default function RAGFrontend() {
  const [token, setToken] = useState<string | null>(null)
  const [file, setFile] = useState<File | null>(null)
  const [access, setAccess] = useState("public")
  const [group, setGroup] = useState("")
  const [uploadStatus, setUploadStatus] = useState<string | null>(null)
  const [query, setQuery] = useState("")
  const [response, setResponse] = useState<string | null>(null)

  const login = async () => {
    const result = await msalInstance.loginPopup({ scopes: ["openid", "profile", "email"] })
    const accounts = msalInstance.getAllAccounts()
    if (accounts.length > 0) {
      const tokenResult = await msalInstance.acquireTokenSilent({ scopes: ["openid"], account: accounts[0] })
      setToken(tokenResult.accessToken)
    }
  }

  const upload = async () => {
    if (!file || !token) return
    const form = new FormData()
    form.append("file", file)
    form.append("access", access)
    if (access === "restricted") form.append("group", group)
    setUploadStatus("Uploading...")
    const res = await fetch(`${API_BASE}/upload`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    })
    const data = await res.json()
    setUploadStatus(res.ok ? "Upload erfolgreich" : `Fehler: ${data.detail || "Unknown"}`)
  }

  const ask = async () => {
    if (!query || !token) return
    setResponse("...")
    const res = await fetch(`${API_BASE}/search?query=${encodeURIComponent(query)}`, {
      headers: { Authorization: `Bearer ${token}` },
    })
    const data = await res.json()
    setResponse(res.ok ? data.answer : `Fehler: ${data.detail || "Unknown"}`)
  }

  return (
    <div className="p-4 space-y-4">
      {!token ? (
        <Button onClick={login}>Login mit Azure</Button>
      ) : (
        <>
          <Card>
            <CardContent className="space-y-2 p-4">
              <h2 className="text-xl font-bold">📤 Dokument hochladen</h2>
              <Input type="file" onChange={e => setFile(e.target.files?.[0] || null)} />
              <select onChange={e => setAccess(e.target.value)} value={access}>
                <option value="public">Öffentlich</option>
                <option value="restricted">Eingeschränkt (Gruppe)</option>
              </select>
              {access === "restricted" && <Input placeholder="Gruppe" value={group} onChange={e => setGroup(e.target.value)} />}
              <Button onClick={upload}>Hochladen</Button>
              {uploadStatus && <p>{uploadStatus}</p>}
            </CardContent>
          </Card>

          <Card>
            <CardContent className="space-y-2 p-4">
              <h2 className="text-xl font-bold">🤖 Frage stellen</h2>
              <Input value={query} onChange={e => setQuery(e.target.value)} placeholder="Was möchtest du wissen?" />
              <Button onClick={ask}>Fragen</Button>
              {response && <p className="mt-2 whitespace-pre-wrap">{response}</p>}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}