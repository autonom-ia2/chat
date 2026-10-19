// #1426 (tema 4a) — o estado real de um material da base, em palavras para o dono:
//   lendo     → o arquivo ou site ainda está sendo lido (com progresso por página ou lote, 4c);
//   revisando → já foi lido, mas a revisão ainda não terminou: NÃO é "Pronto";
//   atencao   → a revisão reprovou ou uma conferência achou um problema neste material;
//   falha     → não deu para ler;
//   pronto    → lido e aprovado na revisão, sem problema aberto.
// Hoje a página chama de "Pronto" tudo que está `ready`, mesmo antes da revisão: o begin_ingestion!
// grava review_status 'needs_review' no começo e o polling da store para quando a leitura termina,
// por isso a reprovação, que chega depois, só aparece ao recarregar. O sinal de "revisão terminou"
// já existe na API: `review.reviewed_at`.
export const ESTADO_MATERIAL = {
  LENDO: 'lendo',
  REVISANDO: 'revisando',
  ATENCAO: 'atencao',
  FALHA: 'falha',
  PRONTO: 'pronto',
};

const LENDO = ['pending', 'processing'];

export const estadoDoMaterial = (fonte, problemas = []) => {
  if (fonte?.status === 'failed') return ESTADO_MATERIAL.FALHA;
  if (LENDO.includes(fonte?.status)) return ESTADO_MATERIAL.LENDO;
  if (!fonte?.review?.reviewed_at) return ESTADO_MATERIAL.REVISANDO;
  const temProblema = problemas.some(problema =>
    (problema.fontes || []).includes(fonte.id)
  );
  if (fonte.review.status === 'needs_resend' || temProblema) {
    return ESTADO_MATERIAL.ATENCAO;
  }
  return ESTADO_MATERIAL.PRONTO;
};

// 4c — "Página 12 de 80" ou "Parte 3 de 9". Sem progresso conhecido ou antes da primeira página,
// nada (fica só "Lendo…": "página 0 de 80" não diz nada à pessoa).
export const progressoDoMaterial = fonte => {
  const progresso = fonte?.progresso;
  if (!progresso?.total || !(progresso.feito >= 1)) return null;
  const feito = Math.min(progresso.feito || 0, progresso.total);
  return {
    feito,
    total: progresso.total,
    unidade: progresso.unidade === 'lote' ? 'lote' : 'pagina',
  };
};

export const ehFotoDaBase = fonte => fonte?.source_type === 'foto';
