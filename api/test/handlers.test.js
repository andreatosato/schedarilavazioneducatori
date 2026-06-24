const assert = require('node:assert/strict');
const { test } = require('node:test');
const { handleDeleteScheda } = require('../scheda');
const { handleSchede } = require('../schede');

function createContext() {
  return { log: { error() {} }, res: null };
}

test('handleSchede returns listed records on GET', async () => {
  const context = createContext();
  await handleSchede(context, { method: 'GET', query: { continuationToken: 'next' } }, {
    listSchede: async token => ({ items: [{ id: token }], continuationToken: null }),
    toHttpError: () => ({ status: 500 })
  });

  assert.deepEqual(context.res, {
    status: 200,
    body: { items: [{ id: 'next' }], continuationToken: null }
  });
});

test('handleSchede creates a record on POST', async () => {
  const context = createContext();
  await handleSchede(context, { method: 'POST', body: { id: 'scheda_2' } }, {
    createScheda: async input => input,
    toHttpError: () => ({ status: 500 })
  });

  assert.deepEqual(context.res, {
    status: 201,
    body: { id: 'scheda_2' }
  });
});

test('handleSchede maps store errors to HTTP responses', async () => {
  const context = createContext();
  await handleSchede(context, { method: 'POST', body: {} }, {
    createScheda: async () => { throw new Error('boom'); },
    toHttpError: () => ({ status: 500, body: { error: 'mapped' } })
  });

  assert.deepEqual(context.res, { status: 500, body: { error: 'mapped' } });
});

test('handleDeleteScheda deletes a record by id', async () => {
  const context = createContext();
  let receivedId;
  await handleDeleteScheda(context, { params: { id: 'scheda_3' } }, {
    deleteScheda: async id => {
      receivedId = id;
      return { id };
    },
    toHttpError: () => ({ status: 500 })
  });

  assert.equal(receivedId, 'scheda_3');
  assert.deepEqual(context.res, { status: 200, body: { id: 'scheda_3' } });
});
