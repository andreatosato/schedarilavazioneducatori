const assert = require('node:assert/strict');
const { test } = require('node:test');
const { normalizeScheda, toHttpError } = require('../shared/schedeStore');

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
