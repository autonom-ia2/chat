// #2898 — "Ajustar renovações": as escolhas da conta e as regras puras da tela
// (o que falta, o que mudou, quantos seguros entram). São três escolhas: em
// que funil e etapa a renovação aparece, quantos dias antes do fim e se as
// mensagens antes de vencer saem. Dias e mensagens já nascem respondidos; o
// funil é a única escolha que a corretora precisa fazer para a renovação andar.
export const MENSAGENS = { MANDAR: 'mandar', NAO_MANDAR: 'nao_mandar' };

export const DIAS_PADRAO = 60;
const DIAS_MINIMO = 1;

export const AJUSTES_PADRAO = Object.freeze({
  funilId: null,
  etapaId: null,
  dias: DIAS_PADRAO,
  mensagens: MENSAGENS.MANDAR,
});

const ehDigito = char => char >= '0' && char <= '9';

// O número de dias que a pessoa escreveu: inteiro a partir de 1, ou null. Só
// algarismos valem: "1e2", "12,5" e "-3" não são um número de dias.
export const diasDigitados = texto => {
  const escrito = String(texto ?? '').trim();
  if (!escrito || ![...escrito].every(ehDigito)) return null;
  const numero = Number(escrito);
  return numero >= DIAS_MINIMO ? numero : null;
};

export const umDiaAMenos = dias => Math.max(DIAS_MINIMO, (dias ?? 0) - 1);
export const umDiaAMais = dias => (dias ?? 0) + 1;

// Quantos seguros entram em renovação com esse número de dias. `vencimentos`:
// em quantos dias cada seguro que ainda vale termina.
export const quantosEntram = (vencimentos = [], dias = DIAS_PADRAO) =>
  dias ? vencimentos.filter(falta => falta >= 0 && falta <= dias).length : 0;

// As etapas do funil escolhido ([] quando o funil não está entre os da conta).
export const etapasDoFunil = (funis = [], funilId = null) =>
  funis.find(funil => funil.id === funilId)?.etapas ?? [];

// Os nomes do funil e da etapa escolhidos, para dizer a escolha de hoje a quem
// só lê. `null` quando a conta ainda não escolheu (ou o funil, ou a etapa, foi
// apagado).
export const ondeFicam = (funis = [], { funilId, etapaId } = {}) => {
  const funil = funis.find(item => item.id === funilId);
  const etapa = funil?.etapas.find(item => item.id === etapaId);
  return etapa ? { funil: funil.nome, etapa: etapa.nome } : null;
};

// O que falta para guardar os ajustes: '' = nada. A ordem é a da tela.
export const FALTAS = { FUNIL: 'FUNIL', ETAPA: 'ETAPA', DIAS: 'DIAS' };
export const faltaNosAjustes = ({ funilId, etapaId, dias } = {}) => {
  if (!funilId) return FALTAS.FUNIL;
  if (!etapaId) return FALTAS.ETAPA;
  return dias ? '' : FALTAS.DIAS;
};

// Escolher o funil já escolhe a primeira etapa dele.
export const comOFunil = (ajustes, funis, funilId) => ({
  ...ajustes,
  funilId,
  etapaId: etapasDoFunil(funis, funilId)[0]?.id ?? null,
});

export const ajustesMudaram = (antes = {}, agora = {}) =>
  Object.keys(AJUSTES_PADRAO).some(chave => antes[chave] !== agora[chave]);
