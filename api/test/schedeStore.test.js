const assert = require('node:assert/strict');
const { test } = require('node:test');
const { normalizeScheda, toHttpError, ConfigurationError } = require('../shared/schedeStore');

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
  const error = new ConfigurationError('COSMOS_CONNECTIONSTRING non configurata');
  assert.deepEqual(toHttpError(error), {
    status: 503,
    body: { error: 'COSMOS_CONNECTIONSTRING non configurata' }
  });
});

test('getContainer throws a ConfigurationError when the connection string is missing', () => {
  const previous = process.env.COSMOS_CONNECTIONSTRING;
  delete process.env.COSMOS_CONNECTIONSTRING;
  try {
    const { getContainer } = require('../shared/schedeStore');
    assert.throws(() => getContainer(), ConfigurationError);
  } finally {
    if (previous === undefined) delete process.env.COSMOS_CONNECTIONSTRING;
    else process.env.COSMOS_CONNECTIONSTRING = previous;
  }
});

test('getContainer treats a whitespace-only connection string as missing', () => {
  const previous = process.env.COSMOS_CONNECTIONSTRING;
  process.env.COSMOS_CONNECTIONSTRING = '   ';
  try {
    const { getContainer } = require('../shared/schedeStore');
    assert.throws(() => getContainer(), ConfigurationError);
  } finally {
    if (previous === undefined) delete process.env.COSMOS_CONNECTIONSTRING;
    else process.env.COSMOS_CONNECTIONSTRING = previous;
  }
});
