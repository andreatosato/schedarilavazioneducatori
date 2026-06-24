const { CosmosClient } = require('@azure/cosmos');

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

let cachedContainer;

class ValidationError extends Error {}

function getContainer() {
  if (cachedContainer) return cachedContainer;

  const connectionString = process.env.COSMOS_CONNECTIONSTRING;
  if (!connectionString) {
    throw new Error('COSMOS_CONNECTIONSTRING non configurata');
  }

  const client = new CosmosClient(connectionString);
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

async function listSchede() {
  const { resources } = await getContainer()
    .items.query('SELECT * FROM c')
    .fetchAll();
  return resources;
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
  return { status: 500, body: { error: 'Errore interno durante l’accesso a Cosmos DB' } };
}

module.exports = {
  ValidationError,
  createScheda,
  deleteScheda,
  listSchede,
  normalizeScheda,
  toHttpError
};
