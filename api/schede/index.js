const { createScheda, listSchede, toHttpError } = require('../shared/schedeStore');

module.exports = async function (context, req) {
  try {
    if (req.method === 'GET') {
      const items = await listSchede();
      context.res = { status: 200, body: { items } };
      return;
    }

    const created = await createScheda(req.body);
    context.res = { status: 201, body: created };
  } catch (error) {
    context.log.error('Errore API schede', error);
    context.res = toHttpError(error);
  }
};
