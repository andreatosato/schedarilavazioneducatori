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
| `staticwebapp.config.json` | Configurazione di Azure Static Web Apps |
| `infra/main.bicep` | Template Bicep per provisioning della Static Web App |
| `infra/main.bicepparam` | Parametri di default per il deploy Bicep |
| `.github/workflows/azure-static-web-apps.yml` | Workflow di deploy automatico su Azure Static Web Apps |

## Deploy su Azure Static Web Apps

Il sito viene pubblicato su [Azure Static Web Apps](https://learn.microsoft.com/azure/static-web-apps/).

### 1. Provisioning dell'infrastruttura (Bicep)

```bash
az group create --name <rg-name> --location westeurope
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

### 2. Configurazione del deploy automatico

1. Recupera il deployment token della Static Web App (`schedari-strade-aperte` è il nome
   di default definito in `infra/main.bicepparam`; usa lo stesso valore se lo hai modificato):
   ```bash
   az staticwebapp secrets list \
     --name schedari-strade-aperte \
     --resource-group <rg-name> \
     --query "properties.apiKey" -o tsv
   ```
2. In GitHub, aggiungi il token come secret del repository con nome `AZURE_STATIC_WEB_APPS_API_TOKEN`
   (**Settings → Secrets and variables → Actions**).
3. Ad ogni push sul branch `main`, il workflow `azure-static-web-apps.yml` pubblica automaticamente il sito.
   Le pull request generano ambienti di staging temporanei.