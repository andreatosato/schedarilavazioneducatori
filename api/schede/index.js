const store = require('../shared/schedeStore');

async function handleSchede(context, req, schedeStore = store) {
  try {
    if (req.method === 'GET') {
      const page = await schedeStore.listSchede(req.query && req.query.continuationToken);
      context.res = { status: 200, body: page };
      return;
    }

    const created = await schedeStore.createScheda(req.body);
    context.res = { status: 201, body: created };
  } catch (error) {
    context.log.error('Errore API schede', error);
    context.res = schedeStore.toHttpError(error);
  }
}

module.exports = handleSchede;
module.exports.handleSchede = handleSchede;
