import React, { useEffect, useState } from "react";
import Keycloak from "keycloak-js";

const keycloak = new Keycloak({
  url: "https://auth.local", // ggf. Caddy-Subdomain
  realm: "myrealm",
  clientId: "frontend",
});

export default function App() {
  const [authenticated, setAuthenticated] = useState(false);
  const [token, setToken] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [query, setQuery] = useState("");
  const [response, setResponse] = useState("");

  useEffect(() => {
    keycloak.init({ onLoad: "login-required" }).then((auth) => {
      if (auth && keycloak.token) {
        setAuthenticated(true);
        setToken(keycloak.token);
      }
    });
  }, []);

  const handleUpload = async () => {
    if (!file) return;
    const formData = new FormData();
    formData.append("file", file);
    const res = await fetch("/api/upload", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body: formData,
    });
    alert(await res.text());
  };

  const handleQuery = async () => {
    const res = await fetch("/api/query", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ query }),
    });
    const data = await res.json();
    setResponse(data.answer || "Keine Antwort");
  };

  if (!authenticated) return <div>Lade Login...</div>;

  return (
    <div style={{ textAlign: "center", padding: "2rem" }}>
      <img src="/logo.png" alt="Logo" style={{ width: 100, marginBottom: 20 }} />
      <h2>Dokument Upload</h2>
      <input type="file" onChange={(e) => setFile(e.target.files?.[0] || null)} />
      <button onClick={handleUpload}>Hochladen</button>
      <h2>Frage stellen</h2>
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Frage eingeben..."
      />
      <button onClick={handleQuery}>Senden</button>
      <p><strong>Antwort:</strong> {response}</p>
    </div>
  );
}
