# Strade Aperte – Scheda di Rilevazione

App web statica per la rilevazione delle uscite educative di strada del progetto **Strade Aperte**.

## Funzionalità

- **Compilazione scheda**: form completo per registrare ogni uscita (data, luogo, educatori, ragazzi incontrati, clima, criticità, rete territoriale, note).
- **Salvataggio locale**: i dati vengono salvati nel `localStorage` del browser, senza necessità di un server.
- **Storico schede**: pagina dedicata per consultare, filtrare e gestire tutte le schede salvate, con statistiche aggregate.
- **Esportazione CSV**: download di tutte le schede in formato CSV per l'analisi in Excel/Sheets.
- **Copia testo**: genera un riepilogo formattato da incollare su WhatsApp o Email.

## Struttura

| File | Descrizione |
|------|-------------|
| `index.html` | Form di compilazione scheda |
| `history.html` | Storico e gestione schede salvate |
| `.nojekyll` | Disabilita Jekyll su GitHub Pages |
| `.github/workflows/deploy.yml` | Workflow di deploy automatico su GitHub Pages |

## Deploy su GitHub Pages

Il sito viene pubblicato automaticamente su GitHub Pages ad ogni push sul branch `main` tramite GitHub Actions.

Per abilitare GitHub Pages:
1. Vai in **Settings → Pages**
2. Seleziona **Source: GitHub Actions**
3. Esegui un push sul branch `main`