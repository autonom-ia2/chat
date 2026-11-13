// #2898 — em que pé está a renovação de um seguro, em palavras de gente: o que
// já foi feito e o que falta (nunca o nome do mecanismo). Função pura: devolve
// o nome da frase e o que ela precisa; quem desenha traduz. O funil e a etapa
// são os que a corretora escolheu, com os nomes que ela deu: a frase repete os
// nomes, sem tentar adivinhar o que cada etapa quer dizer.
export const DESFECHOS = { RENOVOU: 'renovou', NAO_RENOVOU: 'nao_renovou' };

export const MOTIVO_ESCRITO = 'outro';
// Os motivos de um toque, na ordem em que o diálogo os oferece.
export const MOTIVOS = [
  'achou_caro',
  'outra_corretora',
  'vendeu_o_bem',
  'nao_respondeu',
];

export const SITUACOES = {
  EM_ETAPA: 'EM_ETAPA',
  RENOVOU_FALTA: 'RENOVOU_FALTA',
  RENOVOU: 'RENOVOU',
  NAO_RENOVOU: 'NAO_RENOVOU',
  NAO_RENOVOU_MOTIVO: 'NAO_RENOVOU_MOTIVO',
  NAO_RENOVOU_ESCRITO: 'NAO_RENOVOU_ESCRITO',
};

// O seguro renovou quando a renovação fechou como renovada ou quando ele já
// tem a data em que renovou.
export const renovou = seguro =>
  seguro.renovacao?.desfecho === DESFECHOS.RENOVOU ||
  Boolean(seguro.renovadoEm);

export const naoRenovou = seguro =>
  seguro.renovacao?.desfecho === DESFECHOS.NAO_RENOVOU;

// A renovação terminou (de um jeito ou de outro): dá para desfazer.
export const terminou = seguro => renovou(seguro) || naoRenovou(seguro);

// Renovou e a apólice nova ainda não foi guardada.
export const faltaApoliceNova = seguro =>
  renovou(seguro) && !seguro.apoliceNova;

// Não renovou e ninguém disse por quê.
export const faltaMotivo = seguro => naoRenovou(seguro) && !seguro.motivo;

const doNaoRenovou = seguro => {
  if (!seguro.motivo) return { id: SITUACOES.NAO_RENOVOU };
  return seguro.motivo === MOTIVO_ESCRITO && seguro.motivoEscrito
    ? { id: SITUACOES.NAO_RENOVOU_ESCRITO, texto: seguro.motivoEscrito }
    : { id: SITUACOES.NAO_RENOVOU_MOTIVO, motivo: seguro.motivo };
};

// `null` quando o seguro não tem renovação.
export const situacaoDaRenovacao = seguro => {
  if (!seguro?.renovacao) return null;
  if (naoRenovou(seguro)) return doNaoRenovou(seguro);
  if (renovou(seguro)) {
    return {
      id: seguro.apoliceNova ? SITUACOES.RENOVOU : SITUACOES.RENOVOU_FALTA,
    };
  }
  const { funil, etapa } = seguro.renovacao;
  return { id: SITUACOES.EM_ETAPA, funil, etapa };
};
