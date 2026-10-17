// Registro de ligação do WhatsApp (#1702). O servidor grava uma mensagem de aviso
// (activity) com content_attributes.waha_call_summary =
// { call_id, outcome: 'missed' | 'rejected' | 'accepted', is_video, at }.
// Com a pele, a linha de aviso vira o cartão de ligação do app.

export const RESULTADOS = ['missed', 'rejected', 'accepted'];

export const resumoDaLigacao = atributos => {
  const resumo = atributos?.wahaCallSummary;
  if (!resumo || !RESULTADOS.includes(resumo.outcome)) return null;
  return {
    resultado: resumo.outcome,
    video: Boolean(resumo.isVideo),
    // `at` é iso8601; a hora do cartão usa segundos, como o created_at.
    quando: resumo.at ? Math.floor(Date.parse(resumo.at) / 1000) || null : null,
  };
};

// Perdida e recusada saem em vermelho, como no app.
export const ligacaoPerdida = resumo =>
  ['missed', 'rejected'].includes(resumo?.resultado);
