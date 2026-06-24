# Strade Aperte – Scheda di Rilevazione

App web statica per la rilevazione delle uscite educative di strada del progetto **Strade Aperte**.

> **App online:** https://black-sand-00abc5803.7.azurestaticapps.net
>
> L'URL definitivo viene generato da Azure Static Web Apps e include un suffisso
> casuale: aggiornalo qui dopo aver eseguito il deploy se differisce.

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
| `infra/main.bicep` | Template Bicep che provisiona solo Cosmos DB Free Tier |
| `infra/main.bicepparam` | Parametri di default per il deploy Bicep |
| `.github/workflows/azure-static-web-apps-black-sand-00abc5803.yml` | Workflow di deploy automatico su Azure Static Web Apps |

## Architettura su Azure

L'infrastruttura è mantenuta il più economica possibile:

- **Azure Static Web Apps** (piano *Free*, gratuito) ospita il sito statico.
- La pipeline di infrastruttura crea solo **Azure Cosmos DB for NoSQL** in *Free Tier* (1000 RU/s + 25 GB gratuiti a vita), con database e container `schede`.
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
3. Il resource provider `Microsoft.DocumentDB` registrato (di norma lo è già):
   ```bash
   az provider register --namespace Microsoft.DocumentDB
   ```
4. Nessun account Cosmos DB *Free Tier* già presente nella sottoscrizione
   (altrimenti imposta `enableCosmosFreeTier = false`).

### 1. Provisioning dell'infrastruttura (Bicep)

#### Opzione A – Automatico da GitHub Actions (consigliata)

Il workflow `.github/workflows/provision-infra.yml` esegue il Bicep al posto tuo:
crea il resource group e **solo** l'account Cosmos DB Free Tier con database/container
`schede`.

1. Crea un'app/service principal in Entra ID e assegnale il ruolo *Contributor*
   sulla sottoscrizione:
   ```bash
   az ad sp create-for-rbac \
     --name "github-strade-aperte" \
     --role Contributor \
     --scopes /subscriptions/<subscription-id> \
     --sdk-auth
   ```
2. Copia il JSON prodotto dal comando precedente in questo **secret** del repository
   (**Settings → Secrets and variables → Actions**):

   | Secret | Valore |
   |--------|--------|
   | `AZURE_CREDENTIALS` | JSON con `clientId`, `clientSecret`, `subscriptionId`, `tenantId` |

   Opzionalmente puoi impostare le **variables** `AZURE_RESOURCE_GROUP` e `AZURE_LOCATION`
   (default: `rg-strade-aperte` e `westeurope`).
3. Avvia il workflow **Provision Cosmos DB Free Tier** da *Actions → Run workflow*.
   Se la sottoscrizione ha già un altro Cosmos DB Free Tier, imposta
   `enableCosmosFreeTier = false` in `infra/main.bicepparam` oppure elimina l'altro
   account gratuito prima del deploy.

> Se vedi l'errore `AADSTS53003` con OIDC, è una policy di Conditional Access del tenant
> che blocca l'emissione del token. Questo workflow usa `AZURE_CREDENTIALS` proprio per
> evitare la federated credential OIDC; in alternativa devi far escludere/abilitare la
> service principal nelle policy del tenant.

#### Opzione B – Manuale da Azure CLI

```bash
az group create --name <rg-name> --location westeurope
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Al termine, gli output contengono i nomi di account, database e container Cosmos creati.

### 2. Configurazione del deploy automatico

1. Recupera il deployment token della Static Web App (`black-sand-00abc5803` è il nome
   di default definito in `infra/main.bicepparam`; usa lo stesso valore se lo hai modificato):
   ```bash
   az staticwebapp secrets list \
     --name black-sand-00abc5803 \
     --resource-group <rg-name> \
     --query "properties.apiKey" -o tsv
   ```
2. In GitHub, aggiungi il token come secret del repository con nome
   `AZURE_STATIC_WEB_APPS_API_TOKEN_BLACK_SAND_00ABC5803`
   (**Settings → Secrets and variables → Actions**).
3. Ad ogni push sul branch `main`, il workflow `azure-static-web-apps-black-sand-00abc5803.yml`
   pubblica automaticamente il sito e la configurazione Data API Builder in `swa-db-connections`.
   Le pull request generano ambienti di staging temporanei.