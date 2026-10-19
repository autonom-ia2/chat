// #1426 (tema 4a) — o estado real de um material da base, em palavras para o dono (só na Fase 2):
//   lendo     → o arquivo, site ou foto ainda está sendo lido;
//   revisando → já foi lido, mas a revisão ainda não terminou: NÃO é "Pronto";
//   atencao   → a revisão terminou e não aprovou ("Precisa de você"): o agente não usa o material;
//   falha     → não deu para ler;
//   pronto    → lido e aprovado na revisão (ou material de antes da revisão existir, que o agente usa).
// O begin_ingestion! grava review_status 'needs_review' já no começo da leitura; o sinal de que a revisão terminou é
// `review.reviewed_at`.
export const ESTADO_MATERIAL = {
  LENDO: 'lendo',
  REVISANDO: 'revisando',
  ATENCAO: 'atencao',
  FALHA: 'falha',
  PRONTO: 'pronto',
};

const LENDO = ['pending', 'processing'];

// Lido e esperando o parecer. A store se relê enquanto houver um assim: é o que faz a reprovação chegar sem recarregar.
export const aguardandoRevisao = fonte =>
  fonte?.status === 'ready' &&
  fonte?.review?.status === 'needs_review' &&
  !fonte?.review?.reviewed_at;

// #1426 (4b) — um problema das conferências neste material (duplicado, contradição) também pede a pessoa. As páginas de
// fora, não: o material vale com o que foi lido, e o cartão só avisa.
const SO_AVISO = ['paginas_de_fora'];
const temProblema = (fonte, problemas) =>
  problemas.some(
    problema =>
      !SO_AVISO.includes(problema.tipo) &&
      (problema.fontes || []).includes(fonte?.id)
  );

export const estadoDoMaterial = (fonte, problemas = []) => {
  if (fonte?.status === 'failed') return ESTADO_MATERIAL.FALHA;
  if (LENDO.includes(fonte?.status)) return ESTADO_MATERIAL.LENDO;
  if (aguardandoRevisao(fonte)) return ESTADO_MATERIAL.REVISANDO;
  const parecer = fonte?.review?.status;
  if (parecer && parecer !== 'accepted') return ESTADO_MATERIAL.ATENCAO;
  if (temProblema(fonte, problemas)) return ESTADO_MATERIAL.ATENCAO;
  return ESTADO_MATERIAL.PRONTO;
};

export const precisaDeVoce = (fonte, problemas = []) =>
  [ESTADO_MATERIAL.ATENCAO, ESTADO_MATERIAL.FALHA].includes(
    estadoDoMaterial(fonte, problemas)
  );

export const ehFotoDaBase = fonte => fonte?.source_type === 'foto';
