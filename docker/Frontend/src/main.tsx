import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';
import { ReactKeycloakProvider } from '@react-keycloak/web'; // Import hinzugefügt
import Keycloak from 'keycloak-js'; // Import hinzugefügt

// Keycloak-Instanz initialisieren
// Stellen Sie sicher, dass diese Konfiguration mit Ihrer zukünftigen Keycloak-Instanz übereinstimmt.
// Die Werte kommen idealerweise aus Umgebungsvariablen oder einer Konfigurationsdatei.
// Für den Moment nutzen wir die Dummy-Werte aus der .env des Haupt-Setup-Skripts.
const keycloakConfig = {
  url: import.meta.env.VITE_KEYCLOAK_URL || 'https://auth.local', // Aus .env oder Default
  realm: import.meta.env.VITE_KEYCLOAK_REALM || 'mein-unternehmen', // Aus .env oder Default
  clientId: import.meta.env.VITE_KEYCLOAK_CLIENT_ID || 'frontend',   // Aus .env oder Default
};

const keycloak = new Keycloak(keycloakConfig);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {/* KeycloakProvider hinzufügen */}
    <ReactKeycloakProvider authClient={keycloak}>
      <App />
    </ReactKeycloakProvider>
  </React.StrictMode>
);