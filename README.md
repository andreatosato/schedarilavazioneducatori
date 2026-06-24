# Strade Aperte – Scheda di Rilevazione

App web statica per la rilevazione delle uscite educative di strada del progetto **Strade Aperte**.

> **App online:** https://schedari-strade-aperte.azurestaticapps.net
>
> L'URL definitivo viene generato da Azure al primo deploy (output `appUrl` del Bicep) e
> include un suffisso casuale: aggiornalo qui dopo aver eseguito il deploy se differisce.

## Funzionalità

- **Compilazione scheda**: form completo per registrare ogni uscita (data, luogo, educatori, ragazzi incontrati, clima, criticità, rete territoriale, note).
- **Persistenza dati**: le schede vengono salvate su **Azure Cosmos DB** (Free Tier) tramite la *database connection* integrata di Azure Static Web Apps, con fallback locale (`localStorage`/`sessionStorage`) del browser.
- **Storico schede**: pagina dedicata per consultare, filtrare e gestire tutte le schede salvate, con statistiche aggregate.
- **Esportazione CSV**: download di tutte le schede in formato CSV per l'analisi in Excel/Sheets.
- **Copia testo**: genera un riepilogo formattato da incollare su WhatsApp o Email.

## Struttura

| File | Descrizione |
|------|-------------|
| `index.html` | Form di compilazione scheda |
| `history.html` | Storico e gestione schede salvate |
| `staticwebapp.config.json` | Configurazione di Azure Static Web Apps |
| `swa-db-connections/staticwebapp.database.config.json` | Configurazione Data API Builder per Cosmos DB |
| `swa-db-connections/schede.gql` | Schema GraphQL dell'entità Scheda |
| `infra/main.bicep` | Template Bicep che provisiona **tutta** l'infrastruttura (Static Web App + Cosmos DB) |
| `infra/main.bicepparam` | Parametri di default per il deploy Bicep |
| `.github/workflows/azure-static-web-apps.yml` | Workflow di deploy automatico su Azure Static Web Apps |

## Architettura su Azure

L'infrastruttura, creata interamente dal Bicep in un solo deployment, è la più economica possibile:

- **Azure Static Web Apps** (piano *Free*, gratuito) ospita il sito statico.
- **Azure Cosmos DB for NoSQL** in *Free Tier* (1000 RU/s + 25 GB gratuiti a vita) memorizza le schede.
- La **database connection** di Static Web Apps espone Cosmos DB tramite Data API Builder
  (GraphQL su `/data-api/graphql`), senza bisogno di scrivere codice server.

> ℹ️ Il *Free Tier* di Cosmos DB consente **un solo account gratuito per sottoscrizione**.
> Se la sottoscrizione ne ha già uno, imposta `enableCosmosFreeTier = false` in
> `infra/main.bicepparam` (l'account verrà comunque creato, ma con la normale tariffazione).

## Deploy su Azure Static Web Apps

### Prerequisiti per lanciare il Bicep

Per eseguire il Bicep sulla tua sottoscrizione servono:

1. Una **sottoscrizione Azure** attiva e l'[Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installata.
2. Login e selezione della sottoscrizione:
   ```bash
   az login
   az account set --subscription "<id-o-nome-sottoscrizione>"
   ```
3. I resource provider `Microsoft.Web` e `Microsoft.DocumentDB` registrati (di norma lo sono già):
   ```bash
   az provider register --namespace Microsoft.Web
   az provider register --namespace Microsoft.DocumentDB
   ```
4. Nessun account Cosmos DB *Free Tier* già presente nella sottoscrizione
   (altrimenti imposta `enableCosmosFreeTier = false`).

### 1. Provisioning dell'infrastruttura (Bicep)

```bash
az group create --name <rg-name> --location westeurope
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Al termine, l'output `appUrl` contiene l'URL pubblico dell'app.

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