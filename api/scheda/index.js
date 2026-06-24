const store = require('../shared/schedeStore');

async function handleDeleteScheda(context, req, schedeStore = store) {
  try {
    const deleted = await schedeStore.deleteScheda(req.params.id);
    context.res = { status: 200, body: deleted };
  } catch (error) {
    context.log.error('Errore API eliminazione scheda', error);
    context.res = schedeStore.toHttpError(error);
  }
}

module.exports = handleDeleteScheda;
module.exports.handleDeleteScheda = handleDeleteScheda;
