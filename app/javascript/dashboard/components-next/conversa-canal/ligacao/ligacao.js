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

// Ligação da Cloud API (#1702): a mensagem `voice_call` traz o registro em `call`
// ({ status, direction, recordingUrl… }). Com a pele, a ligação encerrada vira o mesmo
// cartão do app. Fica o balão do Chatwoot quando ele tem o que fazer: tocando ou em
// andamento (entrar na ligação), com gravação (ouvir) e a perdida do cliente (ligar
// de volta) — o cartão do app só informa, e essas ações não podem sumir.
const ENCERRADAS = {
  completed: 'accepted',
  'no-answer': 'missed',
  failed: 'missed',
  rejected: 'rejected',
};
const DE_SAIDA = ['outgoing', 'outbound'];
const DE_ENTRADA = ['incoming', 'inbound'];

// Mesma leitura do balão do Chatwoot: a direção da ligação, ou o lado da mensagem.
const ligacaoDeSaida = (chamada, enviada) => {
  if (DE_SAIDA.includes(chamada?.direction)) return true;
  if (DE_ENTRADA.includes(chamada?.direction)) return false;
  return enviada;
};

export const resumoDaLigacaoDaCloud = (chamada, enviada) => {
  const resultado = ENCERRADAS[chamada?.status];
  if (!resultado) return null;
  return {
    resultado,
    video: false,
    quando: null,
    deSaida: ligacaoDeSaida(chamada, enviada),
  };
};

export const ligacaoDaCloudNoCartao = ({ chamada, enviada, anexos }) => {
  const resumo = resumoDaLigacaoDaCloud(chamada, enviada);
  if (!resumo) return false;
  const gravacao =
    Boolean(chamada?.recordingUrl) ||
    (anexos || []).some(anexo => anexo.fileType === 'audio');
  if (gravacao) return false;
  return resumo.deSaida || resumo.resultado === 'accepted';
};
