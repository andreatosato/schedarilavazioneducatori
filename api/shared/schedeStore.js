const { CosmosClient } = require('@azure/cosmos');
const { DefaultAzureCredential } = require('@azure/identity');

const DEFAULT_DATABASE_NAME = 'schede';
const DEFAULT_CONTAINER_NAME = 'schede';
const ALLOWED_FIELDS = [
  'id',
  'data',
  'oraInizio',
  'oraFine',
  'luogo',
  'zona',
  'educatori',
  'tipo',
  'ragazzi',
  'fasce',
  'genere',
  'nuovi',
  'clima',
  'apertura',
  'temi',
  'criticita',
  'criticitaNote',
  'rete',
  'note',
  'urgenza'
];
const ARRAY_FIELDS = new Set(['educatori', 'fasce', 'temi', 'criticita', 'rete']);
const NUMBER_FIELDS = new Set(['ragazzi', 'nuovi', 'clima', 'apertura']);
const LIST_PAGE_SIZE = 100;
const LIST_SCHEDE_QUERY = `SELECT ${ALLOWED_FIELDS.map(field => `c.${field}`).join(', ')} FROM c`;

// Cached per warm Node.js Functions worker.
let cachedContainer;

class ValidationError extends Error {}

class ConfigurationError extends Error {}

function createCosmosClient() {
  // Prefer Microsoft Entra ID (AAD) authentication when an endpoint is
  // configured. This is required when the Cosmos DB account disables local
  // (key-based) authorization (`disableLocalAuth = true`), which makes the
  // connection string return HTTP 401 "Local Authorization is disabled".
  // DefaultAzureCredential uses the Static Web App system-assigned managed
  // identity at runtime.
  const endpoint = (process.env.COSMOS_ENDPOINT || '').trim();
  if (endpoint) {
    return new CosmosClient({
      endpoint,
      aadCredentials: new DefaultAzureCredential()
    });
  }

  // Fallback to key-based authentication via the connection string for
  // environments where local authorization is still enabled.
  const connectionString = (process.env.COSMOS || '').trim();
  if (connectionString) {
    return new CosmosClient(connectionString);
  }

  throw new ConfigurationError(
    'Cosmos DB non configurata: imposta COSMOS_ENDPOINT (autenticazione Entra ID) ' +
      'oppure COSMOS (connection string) nelle Application settings della Static Web App.'
  );
}

function getContainer() {
  if (cachedContainer) return cachedContainer;

  const client = createCosmosClient();
  const databaseName = process.env.COSMOS_DATABASE_NAME || DEFAULT_DATABASE_NAME;
  const containerName = process.env.COSMOS_CONTAINER_NAME || DEFAULT_CONTAINER_NAME;
  cachedContainer = client.database(databaseName).container(containerName);
  return cachedContainer;
}

function normalizeScheda(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new ValidationError('Il payload deve essere un oggetto');
  }
  if (typeof input.id !== 'string' || input.id.trim().length === 0) {
    throw new ValidationError('Il campo id è obbligatorio');
  }

  const scheda = {};
  for (const field of ALLOWED_FIELDS) {
    const value = input[field];
    if (value == null) continue;

    if (ARRAY_FIELDS.has(field)) {
      scheda[field] = Array.isArray(value) ? value.map(item => String(item)) : [];
    } else if (NUMBER_FIELDS.has(field)) {
      const number = Number(value);
      scheda[field] = Number.isFinite(number) ? number : 0;
    } else {
      scheda[field] = String(value);
    }
  }

  return scheda;
}

async function listSchede(continuationToken) {
  const options = { maxItemCount: LIST_PAGE_SIZE };
  if (continuationToken) options.continuationToken = continuationToken;

  const page = await getContainer()
    .items.query(LIST_SCHEDE_QUERY, options)
    .fetchNext();
  return {
    items: page.resources || [],
    continuationToken: page.continuationToken || null
  };
}

async function createScheda(input) {
  const scheda = normalizeScheda(input);
  const { resource } = await getContainer().items.create(scheda);
  return resource;
}

async function deleteScheda(id) {
  if (typeof id !== 'string' || id.trim().length === 0) {
    throw new ValidationError('Id scheda non valido');
  }
  const { resource } = await getContainer().item(id, id).delete();
  return resource || { id };
}

function toHttpError(error) {
  if (error && error.code === 404) {
    return { status: 404, body: { error: 'Scheda non trovata' } };
  }
  if (error && error.code === 409) {
    return { status: 409, body: { error: 'Scheda già esistente' } };
  }
  if (error instanceof ValidationError) {
    return { status: 400, body: { error: error.message } };
  }
  if (error instanceof ConfigurationError) {
    return { status: 503, body: { error: error.message } };
  }
  return { status: 500, body: { error: 'Errore interno durante l’accesso a Cosmos DB' } };
}

module.exports = {
  ValidationError,
  ConfigurationError,
  createScheda,
  deleteScheda,
  getContainer,
  listSchede,
  normalizeScheda,
  toHttpError
};
