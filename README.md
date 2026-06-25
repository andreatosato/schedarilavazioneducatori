# Strade Aperte – Scheda di Rilevazione

App web statica per la rilevazione delle uscite educative di strada del progetto **Strade Aperte**.

> **App online:** https://black-sand-00abc5803.7.azurestaticapps.net
>
> L'URL definitivo viene generato da Azure Static Web Apps e include un suffisso
> casuale: aggiornalo qui dopo aver eseguito il deploy se differisce.

## Funzionalità

- **Compilazione scheda**: form completo per registrare ogni uscita (data, luogo, educatori, ragazzi incontrati, clima, criticità, rete territoriale, note).
- **Persistenza dati**: le schede vengono salvate esclusivamente su **Azure Cosmos DB** (Free Tier) tramite le Azure Functions integrate in Azure Static Web Apps.
- **Storico schede**: pagina dedicata per consultare, filtrare e gestire tutte le schede salvate, con statistiche aggregate.
- **Esportazione CSV**: download di tutte le schede in formato CSV per l'analisi in Excel/Sheets.
- **Copia testo**: genera un riepilogo formattato da incollare su WhatsApp o Email.

## Struttura

| File | Descrizione |
|------|-------------|
| `index.html` | Form di compilazione scheda |
| `history.html` | Storico e gestione schede salvate |
| `staticwebapp.config.json` | Configurazione di Azure Static Web Apps |
| `api/` | Azure Functions HTTP che leggono/scrivono le schede su Cosmos DB |
| `infra/main.bicep` | Template Bicep che provisiona solo Cosmos DB Free Tier |
| `infra/main.bicepparam` | Parametri di default per il deploy Bicep |
| `.github/workflows/azure-static-web-apps-black-sand-00abc5803.yml` | Workflow di deploy automatico su Azure Static Web Apps |

## Architettura su Azure

L'infrastruttura è mantenuta il più economica possibile:

- **Azure Static Web Apps** (piano *Free*, gratuito) ospita il sito statico.
- La pipeline di infrastruttura crea solo **Azure Cosmos DB for NoSQL** in *Free Tier* (1000 RU/s + 25 GB gratuiti a vita), con database e container `schede`.
- Le **Azure Functions** integrate in Static Web Apps espongono solo gli endpoint `/api/schede`
  al frontend e leggono/scrivono direttamente sul container Cosmos DB. L'autenticazione a
  Cosmos DB usa **Microsoft Entra ID (AAD)** tramite la *managed identity* della Static Web App
  (app setting `COSMOS_ENDPOINT`); in alternativa è supportata la connection string `COSMOS`.

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
     --scopes /subscriptions/<subscription-id>
   ```
2. Crea un client secret per l'app Entra ID, poi aggiungi questi **secret** del repository
   (**Settings → Secrets and variables → Actions**):

   | Secret | Valore |
   |--------|--------|
   | `AZURE_CLIENT_ID` | Application (client) ID dell'app Entra ID |
   | `AZURE_CLIENT_SECRET` | Client secret dell'app Entra ID |
   | `AZURE_TENANT_ID` | Tenant ID di Entra ID |
   | `AZURE_SUBSCRIPTION_ID` | ID della sottoscrizione Azure |

   Opzionalmente puoi impostare le **variables** `AZURE_RESOURCE_GROUP` e `AZURE_LOCATION`
   (default: `rg-stradeaperte` e la regione Italy North (`italynorth`)).
3. Avvia il workflow **Provision Cosmos DB Free Tier** da *Actions → Run workflow*.
   La modalità predefinita `validate` compila il Bicep e stampa i comandi manuali
   senza contattare Azure, così non viene bloccata dalle policy di Conditional Access.
   Usa `mode=deploy` solo se la service principal è consentita dalle policy del tenant.
   Se la sottoscrizione ha già un altro Cosmos DB Free Tier, imposta
   `enableCosmosFreeTier = false` in `infra/main.bicepparam` oppure elimina l'altro
   account gratuito prima del deploy.

> Se vedi l'errore `AADSTS53003`, è una policy di Conditional Access del tenant
> che blocca l'emissione del token anche alla service principal. Lascia il workflow
> in `mode=validate` e lancia i comandi stampati da Azure Cloud Shell o da un'altra
> sessione consentita, oppure fai escludere/abilitare la service principal nelle
> policy del tenant prima di usare `mode=deploy`.

#### Opzione B – Manuale da Azure CLI

```bash
az group create --name rg-stradeaperte --location italynorth
az deployment group create \
  --resource-group rg-stradeaperte \
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
     --resource-group rg-stradeaperte \
     --query "properties.apiKey" -o tsv
   ```
2. In GitHub, aggiungi il deployment token come secret del repository
   (**Settings → Secrets and variables → Actions**).

   | Secret | Valore |
   |--------|--------|
   | `AZURE_STATIC_WEB_APPS_API_TOKEN_BLACK_SAND_00ABC5803` | Deployment token della Static Web App |
   | `AZURE_CLIENT_ID` | Client ID del service principal usato per impostare la connection string |
   | `AZURE_TENANT_ID` | Tenant ID del service principal |
   | `AZURE_SUBSCRIPTION_ID` | Subscription ID che contiene la Static Web App e Cosmos DB |

   > 🔐 Lo step *Azure login (OIDC)* usa la **workload identity federation** (OpenID
   > Connect), quindi **non** serve più il secret `AZURE_CLIENT_SECRET`. Configura un
   > *federated credential* sull'app registration (Entra ID → *App registrations* →
   > la tua app → *Certificates & secrets* → *Federated credentials*) con scenario
   > *GitHub Actions deploying Azure resources*. Compila Organization/Repository con
   > `andreatosato` / `schedarilavazioneducatori`, Entity type *Branch* e Branch `main`;
   > il *Subject identifier* risultante è
   > `repo:andreatosato/schedarilavazioneducatori:ref:refs/heads/main` (Issuer
   > `https://token.actions.githubusercontent.com`, Audience `api://AzureADTokenExchange`).
   > Il login con password veniva bloccato dalle policy di Conditional Access del
   > tenant (`AADSTS53003`): l'autenticazione OIDC evita quel blocco. Se la policy
   > si applica anche alle workload identity, escludi la service principal dalla policy.
3. Ad ogni push sul branch `main`, il workflow `azure-static-web-apps-black-sand-00abc5803.yml`
   imposta **automaticamente** l'application setting `COSMOS_ENDPOINT` sulla Static Web App.
   Lo step *Azure login (OIDC)* esegue il login federato con la service principal,
   poi lo step *Configure Cosmos DB endpoint* legge l'endpoint
   dall'account Cosmos (`black-sand-00abc5803-cosmos` nel resource group
   `rg-stradeaperte`) e lo pubblica con `az staticwebapp appsettings set`. La Functions API
   si autentica poi con **Microsoft Entra ID** usando la *managed identity* della Static Web App,
   senza salvare alcuna chiave o connection string nel repository.

   > ℹ️ Perché l'autenticazione AAD funzioni servono due prerequisiti, gestiti dal Bicep
   > (vedi `infra/main.bicep`, `mode=deploy`) ma verificabili anche dal portale:
   > 1. la **system-assigned managed identity** deve essere abilitata sulla Static Web App
   >    (*Static Web App → Identity → System assigned → On*, oppure
   >    `az staticwebapp identity assign`);
   > 2. a quella identità va assegnato il ruolo dati **Cosmos DB Built-in Data Contributor**
   >    sull'account Cosmos (risorsa `sqlRoleAssignments`, role definition
   >    `00000000-0000-0000-0000-000000000002`). Se il login Azure fallisce, lo step salta
   >    l'aggiornamento con un warning senza far fallire il deploy.
4. In alternativa, `COSMOS_ENDPOINT` e il ruolo dati possono essere impostati dal Bicep durante
   il provisioning (vedi `staticWebAppSettings` e `cosmosDataRoleAssignment` in
   `infra/main.bicep`, `mode=deploy`). Se la Static Web App non esiste ancora al momento del
   provisioning, imposta `configureStaticWebAppSettings = false` e `assignCosmosDataRole = false`
   in `infra/main.bicepparam` e rilancia dopo averla creata e dopo aver abilitato la managed identity.
5. Le Azure Functions in `api/` leggono `COSMOS_ENDPOINT` (autenticazione AAD) — oppure
   `COSMOS` (connection string) come fallback — dalle impostazioni dell'app, senza salvare
   segreti nel repository. Le pull request generano ambienti di staging temporanei che **non**
   ereditano le application settings di produzione.

## Risoluzione dei problemi (Cosmos DB)

Se la pagina **Storico** mostra un errore di accesso a Cosmos DB oppure il salvataggio
non va a buon fine, la causa quasi sempre è una configurazione mancante o errata nelle
**Application settings** della Static Web App.

- **Errore `Cosmos DB non configurata` (HTTP 503):** né `COSMOS_ENDPOINT` né `COSMOS`
  sono presenti. Di norma è sufficiente eseguire un nuovo push su `main`: gli step
  *Azure login (OIDC)* e *Configure Cosmos DB endpoint* del workflow impostano
  `COSMOS_ENDPOINT` sulla Static Web App a partire dall'account Cosmos. Se il login
  OIDC fallisce (federated credential mancante o service principal ancora bloccata da
  Conditional Access), lo step viene saltato con un warning: completa la configurazione del
  federated credential. In alternativa puoi (ri)lanciare il provisioning Bicep in
  `mode=deploy` oppure impostarlo manualmente:
  ```bash
  COSMOS_ENDPOINT=$(az cosmosdb show \
    --name <nome-account-cosmos> \
    --resource-group rg-stradeaperte \
    --query "documentEndpoint" -o tsv)
  az staticwebapp appsettings set \
    --name black-sand-00abc5803 \
    --resource-group rg-stradeaperte \
    --setting-names "COSMOS_ENDPOINT=$COSMOS_ENDPOINT"
  ```
- **Errore `Local Authorization is disabled. Use an AAD token...` (HTTP 401, substatus 5202):**
  l'account Cosmos ha disabilitato l'autenticazione locale (`disableLocalAuth = true`), quindi la
  connection string `COSMOS` viene rifiutata. Passa all'autenticazione AAD impostando
  `COSMOS_ENDPOINT` (vedi sopra), abilita la *managed identity* sulla Static Web App e assegnale
  il ruolo **Cosmos DB Built-in Data Contributor**:
  ```bash
  az cosmosdb sql role assignment create \
    --account-name <nome-account-cosmos> \
    --resource-group rg-stradeaperte \
    --role-definition-id 00000000-0000-0000-0000-000000000002 \
    --principal-id <principalId-della-managed-identity-della-SWA> \
    --scope "/"
  ```
- **Errore `Errore interno durante l'accesso a Cosmos DB` (HTTP 500):** la configurazione è
  presente ma l'account/identità non è autorizzato, oppure il database/container
  `schede` non esiste ancora. Verifica di aver completato il *provisioning* dell'infrastruttura
  (vedi *Provisioning dell'infrastruttura*), che `COSMOS_ENDPOINT` punti all'account corretto e
  che la managed identity abbia il ruolo dati.
- Le **Application settings** sono applicate solo all'ambiente di produzione: gli ambienti
  di *staging* generati dalle pull request non le ereditano, quindi su quegli URL Cosmos DB
  risulterà irraggiungibile.
- Dopo aver modificato un'app setting, esegui un nuovo deploy (push su `main`) o attendi il
  riavvio delle Functions affinché il nuovo valore venga letto.
