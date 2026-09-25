// Envio ao CRM em lotes (#680). O servidor aceita até 30 leads por pedido e
// devolve o resultado de cada um; cada lead grava na própria transação. Aqui
// os lotes vão um depois do outro e viram um resumo só. Pedido recusado inteiro
// (rede, 422) vira falha de cada lead dele, e os outros lotes seguem.
export const CRM_BATCH_SIZE = 30;

const REQUEST_FAILED = 'request_failed';

const chunk = (items, size) =>
  Array.from({ length: Math.ceil(items.length / size) }, (_, index) =>
    items.slice(index * size, (index + 1) * size)
  );

const failedBatch = (leadIds, error) =>
  leadIds.map(leadId => ({
    lead_id: leadId,
    reason_code: REQUEST_FAILED,
    message: error?.response?.data?.error || null,
  }));

const batchResult = async (leadIds, request) => {
  try {
    const { data } = await request(leadIds);
    const { created = [], existing = [], failed = [] } = data.payload;
    return { created, existing, failed };
  } catch (error) {
    return { created: [], existing: [], failed: failedBatch(leadIds, error) };
  }
};

export const sendInBatches = (leadIds, request, onProgress = () => {}) => {
  let done = 0;

  // Um lote por vez: o servidor limita o tamanho e a ordem fica a da tela.
  const sendNext = async (previous, batch) => {
    const summary = await previous;
    const result = await batchResult(batch, request);
    done += batch.length;
    onProgress(done);
    return {
      created: [...summary.created, ...result.created],
      existing: [...summary.existing, ...result.existing],
      failed: [...summary.failed, ...result.failed],
    };
  };
  const empty = { created: [], existing: [], failed: [] };

  return chunk(leadIds, CRM_BATCH_SIZE).reduce(
    sendNext,
    Promise.resolve(empty)
  );
};

// success: nada falhou; partial: algo foi e algo falhou; failed: nada foi.
export const sendOutcome = ({ created, existing, failed }) => {
  if (!failed.length) return 'success';
  return created.length || existing.length ? 'partial' : 'failed';
};
