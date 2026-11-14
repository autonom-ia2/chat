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

// Quem põe é o servidor, quando o seguro é marcado como cancelado com a
// renovação aberta: ninguém escolhe este motivo no diálogo.
export const MOTIVO_DO_CANCELAMENTO = 'cancelou';
// Os motivos que têm nome no catálogo. O servidor pode ganhar um motivo antes
// da tela: o que não está aqui nunca aparece como chave crua.
const MOTIVOS_COM_NOME = [...MOTIVOS, MOTIVO_ESCRITO, MOTIVO_DO_CANCELAMENTO];
export const motivoTemNome = motivo => MOTIVOS_COM_NOME.includes(motivo);

export const SITUACOES = {
  EM_ETAPA: 'EM_ETAPA',
  EM_ANDAMENTO: 'EM_ANDAMENTO',
  RENOVOU_FALTA: 'RENOVOU_FALTA',
  RENOVOU: 'RENOVOU',
  NAO_RENOVOU: 'NAO_RENOVOU',
  NAO_RENOVOU_SO: 'NAO_RENOVOU_SO',
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

// O seguro tem renovação, mas quem olha não enxerga o card dela no funil: o
// servidor manda a renovação sem `cardId` (só com o desfecho). Quem não
// enxerga o card quase nunca pode fechá-lo, e botão que só dá erro não ajuda:
// para essa pessoa a renovação é só leitura, e quem cuida dela marca o
// resultado. O seguro sem renovação nenhuma (`renovacao` nula) não entra aqui.
export const renovacaoSoDeLeitura = seguro =>
  Boolean(seguro?.renovacao) && !seguro.renovacao.cardId;

// A renovação terminou (de um jeito ou de outro): dá para desfazer.
export const terminou = seguro => renovou(seguro) || naoRenovou(seguro);

// Renovou e a apólice nova ainda não foi guardada.
export const faltaApoliceNova = seguro =>
  renovou(seguro) && !seguro.apoliceNova;

// Não renovou e ninguém disse por quê.
export const faltaMotivo = seguro => naoRenovou(seguro) && !seguro.motivo;

// O motivo que a tela não conhece vira só "Não renovou.": alguém disse o
// motivo, então a tela não convida a dizer de novo nem escreve o que não sabe.
const doNaoRenovou = seguro => {
  if (!seguro.motivo) return { id: SITUACOES.NAO_RENOVOU };
  if (seguro.motivo === MOTIVO_ESCRITO && seguro.motivoEscrito) {
    return { id: SITUACOES.NAO_RENOVOU_ESCRITO, texto: seguro.motivoEscrito };
  }
  return motivoTemNome(seguro.motivo)
    ? { id: SITUACOES.NAO_RENOVOU_MOTIVO, motivo: seguro.motivo }
    : { id: SITUACOES.NAO_RENOVOU_SO };
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
  // Quem não enxerga o card no funil recebe a renovação só com o desfecho,
  // sem o funil nem a etapa: a frase diz que ela está em andamento e que quem
  // cuida dela marca o resultado.
  const { funil, etapa } = seguro.renovacao;
  return funil && etapa
    ? { id: SITUACOES.EM_ETAPA, funil, etapa }
    : { id: SITUACOES.EM_ANDAMENTO };
};
