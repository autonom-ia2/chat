// #2897 — o selo de um seguro, pela data de hoje. Função pura: a tela e a fonte
// usam a mesma regra. (No protótipo as datas são relativas ao "agora"; na
// entrega real o dia vira no fuso da conta.)
import { DIA_EM_MS } from './grupos';

export const SELOS = {
  ATIVO: 'ativo',
  EM_RENOVACAO: 'em_renovacao',
  RENOVADO: 'renovado',
  VENCIDO: 'vencido',
  CANCELADO: 'cancelado',
  EM_OUTRA_CORRETORA: 'em_outra_corretora',
};
export const SELO_PARCELA_ATRASADA = 'parcela_atrasada';
export const DIAS_DA_RENOVACAO = 60;

// Dias até o seguro terminar; negativo quando já terminou.
export const diasParaTerminar = (seguro, agora = Date.now()) =>
  Math.round((seguro.termina * 1000 - agora) / DIA_EM_MS);

export const diasDesde = (segundos, agora = Date.now()) =>
  Math.round((agora - segundos * 1000) / DIA_EM_MS);

export const seloDoSeguro = (seguro, agora = Date.now()) => {
  if (seguro.deFora) return SELOS.EM_OUTRA_CORRETORA;
  if (seguro.canceladoEm) return SELOS.CANCELADO;
  if (seguro.renovadoEm) return SELOS.RENOVADO;
  const dias = diasParaTerminar(seguro, agora);
  if (dias < 0) return SELOS.VENCIDO;
  if (dias <= DIAS_DA_RENOVACAO && seguro.renovacao) return SELOS.EM_RENOVACAO;
  return SELOS.ATIVO;
};

export const temParcelaAtrasada = seguro => Boolean(seguro.parcelaAbertaEm);

// Conta como "na carteira, valendo": entra nos grupos de vencimento.
export const estaValendo = (seguro, agora = Date.now()) =>
  [SELOS.ATIVO, SELOS.EM_RENOVACAO].includes(seloDoSeguro(seguro, agora));

// O que aparece ao lado do nome na lista de pessoas: só o que pede atenção.
// Ativo e Cancelado não aparecem ("Cliente" já diz que tem seguro).
const URGENCIA = [
  SELOS.VENCIDO,
  SELO_PARCELA_ATRASADA,
  SELOS.EM_RENOVACAO,
  SELOS.RENOVADO,
];

const selosDe = (seguro, agora) => [
  seloDoSeguro(seguro, agora),
  ...(temParcelaAtrasada(seguro) ? [SELO_PARCELA_ATRASADA] : []),
];

// { selo, seguro } do mais urgente, ou null quando nenhum pede atenção.
export const maisUrgente = (seguros = [], agora = Date.now()) =>
  URGENCIA.reduce((achado, selo) => {
    if (achado) return achado;
    const seguro = seguros
      .filter(item => selosDe(item, agora).includes(selo))
      .sort((a, b) => a.termina - b.termina)[0];
    return seguro ? { selo, seguro } : null;
  }, null);

// Ordem do bloco Seguros da ficha: o mais urgente primeiro, cancelado e o de
// outra corretora no fim; no empate, quem termina antes.
const PESO = {
  [SELOS.VENCIDO]: 0,
  [SELOS.EM_RENOVACAO]: 1,
  [SELOS.RENOVADO]: 2,
  [SELOS.ATIVO]: 3,
  [SELOS.EM_OUTRA_CORRETORA]: 4,
  [SELOS.CANCELADO]: 5,
};
const pesoDe = (seguro, agora) => {
  const selo = seloDoSeguro(seguro, agora);
  return selo === SELOS.ATIVO && temParcelaAtrasada(seguro) ? 0.5 : PESO[selo];
};

export const porUrgencia = (seguros = [], agora = Date.now()) =>
  [...seguros].sort(
    (a, b) =>
      pesoDe(a, agora) - pesoDe(b, agora) ||
      a.termina - b.termina ||
      a.id - b.id
  );
