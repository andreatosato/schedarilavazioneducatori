const { deleteScheda, toHttpError } = require('../shared/schedeStore');

module.exports = async function (context, req) {
  try {
    const deleted = await deleteScheda(req.params.id);
    context.res = { status: 200, body: deleted };
  } catch (error) {
    context.log.error('Errore API eliminazione scheda', error);
    context.res = toHttpError(error);
  }
};
