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
// Tracks whether the cached container was built with Entra ID (AAD)
// authentication, so a runtime auth failure can fall back to the
// connection string without retrying the broken credential.
let cachedContainerUsesAad = false;

class ValidationError extends Error {}

class ConfigurationError extends Error {}

class AuthenticationError extends Error {}

function readEndpoint() {
  return (process.env.COSMOS_ENDPOINT || '').trim();
}

function readConnectionString() {
  return (process.env.COSMOS || '').trim();
}

// Detects failures originating from the Entra ID credential chain (for
// example when the Static Web App managed identity is unavailable and
// DefaultAzureCredential falls through to the broken Cloud Shell path,
// raising "Cannot read properties of undefined (reading 'expires_on')").
function isCredentialError(error) {
  if (!error) return false;
  const name = error.name || '';
  if (
    name === 'AggregateAuthenticationError' ||
    name === 'CredentialUnavailableError' ||
    name === 'AuthenticationRequiredError'
  ) {
    return true;
  }
  if (Array.isArray(error.errors) && error.errors.some(isCredentialError)) {
    return true;
  }
  return isCredentialError(error.cause);
}

function buildContainer(client) {
  const databaseName = process.env.COSMOS_DATABASE_NAME || DEFAULT_DATABASE_NAME;
  const containerName = process.env.COSMOS_CONTAINER_NAME || DEFAULT_CONTAINER_NAME;
  return client.database(databaseName).container(containerName);
}

function createAadContainer(endpoint) {
  // Microsoft Entra ID (AAD) authentication is required when the Cosmos DB
  // account disables local (key-based) authorization (`disableLocalAuth = true`),
  // which makes the connection string return HTTP 401 "Local Authorization is
  // disabled". DefaultAzureCredential uses the Static Web App managed identity
  // at runtime.
  return buildContainer(new CosmosClient({ endpoint, aadCredentials: new DefaultAzureCredential() }));
}

function createConnectionStringContainer(connectionString) {
  // Key-based authentication via the connection string, used when local
  // authorization is enabled or as a fallback when AAD authentication is
  // unavailable at runtime.
  return buildContainer(new CosmosClient(connectionString));
}

function getContainer() {
  if (cachedContainer) return cachedContainer;

  const endpoint = readEndpoint();
  if (endpoint) {
    cachedContainer = createAadContainer(endpoint);
    cachedContainerUsesAad = true;
    return cachedContainer;
  }

  const connectionString = readConnectionString();
  if (connectionString) {
    cachedContainer = createConnectionStringContainer(connectionString);
    cachedContainerUsesAad = false;
    return cachedContainer;
  }

  throw new ConfigurationError(
    'Cosmos DB non configurata: imposta COSMOS_ENDPOINT (autenticazione Entra ID) ' +
      'oppure COSMOS (connection string) nelle Application settings della Static Web App.'
  );
}

// Runs a Cosmos operation, recovering from Entra ID credential failures by
// retrying once with the connection string when one is configured. If no
// fallback is available the error is surfaced as an AuthenticationError so the
// HTTP layer can return a clear 503 instead of a generic 500.
async function withContainer(operation) {
  try {
    return await operation(getContainer());
  } catch (error) {
    if (!isCredentialError(error) || !cachedContainerUsesAad) {
      throw error;
    }

    const connectionString = readConnectionString();
    if (!connectionString) {
      throw new AuthenticationError(
        'Autenticazione a Cosmos DB con identità gestita (Entra ID) non riuscita: ' +
          'verifica che la managed identity della Static Web App sia abilitata e ' +
          'che le sia assegnato il ruolo dati su Cosmos DB, oppure configura la ' +
          'connection string COSMOS come fallback.'
      );
    }

    cachedContainer = createConnectionStringContainer(connectionString);
    cachedContainerUsesAad = false;
    return await operation(cachedContainer);
  }
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

  const page = await withContainer(container =>
    container.items.query(LIST_SCHEDE_QUERY, options).fetchNext()
  );
  return {
    items: page.resources || [],
    continuationToken: page.continuationToken || null
  };
}

async function createScheda(input) {
  const scheda = normalizeScheda(input);
  const { resource } = await withContainer(container => container.items.create(scheda));
  return resource;
}

async function deleteScheda(id) {
  if (typeof id !== 'string' || id.trim().length === 0) {
    throw new ValidationError('Id scheda non valido');
  }
  const { resource } = await withContainer(container => container.item(id, id).delete());
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
  if (error instanceof AuthenticationError) {
    return { status: 503, body: { error: error.message } };
  }
  return { status: 500, body: { error: 'Errore interno durante l’accesso a Cosmos DB' } };
}

module.exports = {
  ValidationError,
  ConfigurationError,
  AuthenticationError,
  createScheda,
  deleteScheda,
  getContainer,
  isCredentialError,
  listSchede,
  normalizeScheda,
  toHttpError
};
