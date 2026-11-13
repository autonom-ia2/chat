// #2897 — os grupos da aba Seguros. Cada grupo responde a uma pergunta de quem
// cuida da carteira ("quem vence esta semana?"). São os que o servidor conta
// (Carteira::Consulta): os de vencimento acumulam ("em até 30 dias" inclui quem
// vence amanhã) e só contam seguro que ainda vale. A regra de quem pertence a
// cada grupo, aqui embaixo, é a que a demonstração usa.
// #2898 — a renovação soma o grupo "Em renovação" e os temporários "Não
// renovaram (últimos N dias)", que só aparecem quando a tela de resultados
// leva até eles (`?grupo=<id>`).
import { PERIODOS, grupoDosQueNaoRenovaram } from '../carteira/resultados';
import {
  SELOS,
  diasParaTerminar,
  estaValendo,
  seloDoSeguro,
} from './selosDoSeguro';

export const ABA_SEGUROS = 'seguros';
export const GRUPO_PADRAO_DE_SEGUROS = 'todos';
export const GRUPO_VENCIDO = 'vencido';
export const GRUPO_EM_RENOVACAO = 'em_renovacao';
export const GRUPO_SEM_TELEFONE = 'sem_telefone';

const grupo = (id, chave, comExplicacao = true) => ({
  id,
  nome: `RELACIONAMENTOS_CARTEIRA.GRUPOS.${chave}.NOME`,
  explicacao: comExplicacao
    ? `RELACIONAMENTOS_CARTEIRA.GRUPOS.${chave}.EXPLICACAO`
    : '',
});

export const GRUPOS_DE_SEGUROS = [
  grupo(GRUPO_PADRAO_DE_SEGUROS, 'TODOS', false),
  grupo('vence_7_dias', 'VENCE_7_DIAS'),
  grupo('vence_30_dias', 'VENCE_30_DIAS'),
  grupo('vence_90_dias', 'VENCE_90_DIAS'),
  grupo(GRUPO_EM_RENOVACAO, 'EM_RENOVACAO'),
  grupo(GRUPO_VENCIDO, 'VENCIDO'),
  grupo(GRUPO_SEM_TELEFONE, 'SEM_TELEFONE'),
];

const TEMPORARIOS = PERIODOS.map(dias =>
  grupo(grupoDosQueNaoRenovaram(dias), `NAO_RENOVARAM_${dias}`)
);

// O grupo temporário com esse id, ou null.
export const grupoTemporario = id =>
  TEMPORARIOS.find(item => item.id === id) ?? null;

// Um grupo que o endereço pode pedir (`?grupo=`): um dos de sempre ou um
// temporário. O que não é grupo vira ''.
export const grupoConhecido = id =>
  [...GRUPOS_DE_SEGUROS, ...TEMPORARIOS].some(item => item.id === id) ? id : '';

// Os grupos que a barra mostra: os de sempre e, no fim, o temporário pedido.
export const gruposDaBarra = (temporario = '') =>
  [...GRUPOS_DE_SEGUROS, grupoTemporario(temporario)].filter(Boolean);

const venceEmAte = dias => (seguro, agora) =>
  estaValendo(seguro, agora) && diasParaTerminar(seguro, agora) <= dias;

// Terminou nos últimos N dias sem renovar, tenha alguém dito "não renovou" ou
// não: é a conta do servidor (Carteira::Consulta). O cancelado não chegou ao
// fim, o renovado renovou e o que ainda vale não terminou: nenhum deles entra.
const naoRenovouEmAte = dias => (seguro, agora) =>
  seloDoSeguro(seguro, agora) === SELOS.VENCIDO &&
  -diasParaTerminar(seguro, agora) <= dias;

const REGRAS = {
  [GRUPO_PADRAO_DE_SEGUROS]: () => true,
  vence_7_dias: venceEmAte(7),
  vence_30_dias: venceEmAte(30),
  vence_90_dias: venceEmAte(90),
  [GRUPO_EM_RENOVACAO]: (seguro, agora) =>
    seloDoSeguro(seguro, agora) === SELOS.EM_RENOVACAO,
  ...Object.fromEntries(
    PERIODOS.map(dias => [grupoDosQueNaoRenovaram(dias), naoRenovouEmAte(dias)])
  ),
  [GRUPO_VENCIDO]: (seguro, agora) =>
    seloDoSeguro(seguro, agora) === SELOS.VENCIDO,
  [GRUPO_SEM_TELEFONE]: seguro => !seguro.pessoa?.phone_number,
};

export const seguroPertenceAoGrupo = (seguro, grupoId, agora = Date.now()) => {
  const regra = REGRAS[grupoId];
  return regra ? regra(seguro, agora) : false;
};
