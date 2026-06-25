const assert = require('node:assert/strict');
const { test } = require('node:test');
const {
  normalizeScheda,
  toHttpError,
  ConfigurationError,
  AuthenticationError,
  isCredentialError
} = require('../shared/schedeStore');

test('normalizeScheda keeps only expected fields and coerces values', () => {
  const scheda = normalizeScheda({
    id: 'scheda_1',
    data: '2026-06-24',
    educatori: ['Ada', 42],
    ragazzi: '3',
    clima: 'not-a-number',
    extra: 'ignored'
  });

  assert.deepEqual(scheda, {
    id: 'scheda_1',
    data: '2026-06-24',
    educatori: ['Ada', '42'],
    ragazzi: 3,
    clima: 0
  });
});

test('normalizeScheda handles nullable and invalid array fields', () => {
  const scheda = normalizeScheda({
    id: 'scheda_arrays',
    educatori: null,
    fasce: [],
    temi: 'non-array'
  });

  assert.deepEqual(scheda, {
    id: 'scheda_arrays',
    fasce: [],
    temi: []
  });
});

test('normalizeScheda requires a non-empty id', () => {
  assert.throws(() => normalizeScheda({ id: '' }), /id è obbligatorio/);
});

test('toHttpError maps Cosmos conflicts to HTTP 409', () => {
  assert.deepEqual(toHttpError({ code: 409 }), {
    status: 409,
    body: { error: 'Scheda già esistente' }
  });
});

test('toHttpError maps a missing connection string to HTTP 503', () => {
  const error = new ConfigurationError('COSMOS non configurata');
  assert.deepEqual(toHttpError(error), {
    status: 503,
    body: { error: 'COSMOS non configurata' }
  });
});

test('toHttpError maps an Entra ID authentication failure to HTTP 503', () => {
  const error = new AuthenticationError('Managed identity non disponibile');
  assert.deepEqual(toHttpError(error), {
    status: 503,
    body: { error: 'Managed identity non disponibile' }
  });
});

test('isCredentialError detects ChainedTokenCredential failures', () => {
  const aggregate = new Error('ChainedTokenCredential authentication failed.');
  aggregate.name = 'AggregateAuthenticationError';
  aggregate.errors = [
    Object.assign(new Error('EnvironmentCredential is unavailable.'), {
      name: 'CredentialUnavailableError'
    })
  ];
  assert.equal(isCredentialError(aggregate), true);
});

test('isCredentialError detects the Cloud Shell expires_on failure via cause', () => {
  const credentialError = Object.assign(
    new Error('ManagedIdentityCredential: Authentication failed.'),
    {
      name: 'CredentialUnavailableError',
      cause: new TypeError("Cannot read properties of undefined (reading 'expires_on')")
    }
  );
  assert.equal(isCredentialError(credentialError), true);
});

test('isCredentialError ignores unrelated Cosmos errors', () => {
  assert.equal(isCredentialError({ code: 404 }), false);
  assert.equal(isCredentialError(new Error('Request rate is large')), false);
  assert.equal(isCredentialError(null), false);
});

test('getContainer throws a ConfigurationError when no auth is configured', () => {
  const previousCs = process.env.COSMOS;
  const previousEndpoint = process.env.COSMOS_ENDPOINT;
  delete process.env.COSMOS;
  delete process.env.COSMOS_ENDPOINT;
  try {
    const { getContainer } = require('../shared/schedeStore');
    assert.throws(() => getContainer(), ConfigurationError);
  } finally {
    if (previousCs === undefined) delete process.env.COSMOS;
    else process.env.COSMOS = previousCs;
    if (previousEndpoint === undefined) delete process.env.COSMOS_ENDPOINT;
    else process.env.COSMOS_ENDPOINT = previousEndpoint;
  }
});

test('getContainer treats whitespace-only auth values as missing', () => {
  const previousCs = process.env.COSMOS;
  const previousEndpoint = process.env.COSMOS_ENDPOINT;
  process.env.COSMOS = '   ';
  process.env.COSMOS_ENDPOINT = '   ';
  try {
    const { getContainer } = require('../shared/schedeStore');
    assert.throws(() => getContainer(), ConfigurationError);
  } finally {
    if (previousCs === undefined) delete process.env.COSMOS;
    else process.env.COSMOS = previousCs;
    if (previousEndpoint === undefined) delete process.env.COSMOS_ENDPOINT;
    else process.env.COSMOS_ENDPOINT = previousEndpoint;
  }
});

test('getContainer uses Entra ID auth when COSMOS_ENDPOINT is set', () => {
  const previousCs = process.env.COSMOS;
  const previousEndpoint = process.env.COSMOS_ENDPOINT;
  // No connection string is provided, so this only succeeds via the AAD path.
  delete process.env.COSMOS;
  process.env.COSMOS_ENDPOINT = 'https://example.documents.azure.com:443/';
  try {
    delete require.cache[require.resolve('../shared/schedeStore')];
    const { getContainer } = require('../shared/schedeStore');
    const container = getContainer();
    assert.equal(typeof container.items.query, 'function');
  } finally {
    delete require.cache[require.resolve('../shared/schedeStore')];
    if (previousCs === undefined) delete process.env.COSMOS;
    else process.env.COSMOS = previousCs;
    if (previousEndpoint === undefined) delete process.env.COSMOS_ENDPOINT;
    else process.env.COSMOS_ENDPOINT = previousEndpoint;
  }
});
