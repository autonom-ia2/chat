// #2897 — os grupos da aba Seguros. Cada grupo responde a uma pergunta de quem
// cuida da carteira ("quem vence esta semana?"). Só a regra: a tela e a fonte
// usam as mesmas funções. Os de vencimento acumulam: "em até 30 dias" inclui
// quem vence amanhã.
import { PERIODOS, grupoDosQueNaoRenovaram } from '../carteira/resultados';
import {
  SELOS,
  diasDesde,
  diasParaTerminar,
  estaValendo,
  seloDoSeguro,
  temParcelaAtrasada,
} from './selosDoSeguro';

export const ABA_SEGUROS = 'seguros';
export const GRUPO_PADRAO_DE_SEGUROS = 'todos';
export const GRUPO_SO_UM_SEGURO = 'so_um_seguro';

const grupo = (id, chave, comExplicacao = true) => ({
  id,
  nome: `RELACIONAMENTOS_CARTEIRA.GRUPOS.${chave}.NOME`,
  explicacao: comExplicacao
    ? `RELACIONAMENTOS_CARTEIRA.GRUPOS.${chave}.EXPLICACAO`
    : '',
});

const GRUPO_PARCELA = 'parcela_atrasada';
export const GRUPO_SEM_TELEFONE = 'sem_telefone';

const TODOS_OS_GRUPOS = [
  grupo('todos', 'TODOS', false),
  grupo('vence_7_dias', 'VENCE_7_DIAS'),
  grupo('vence_30_dias', 'VENCE_30_DIAS'),
  grupo('vence_90_dias', 'VENCE_90_DIAS'),
  grupo('em_renovacao', 'EM_RENOVACAO'),
  grupo('vencido', 'VENCIDO'),
  grupo(GRUPO_SEM_TELEFONE, 'SEM_TELEFONE'),
  grupo(GRUPO_PARCELA, 'PARCELA_ATRASADA'),
];

// Os grupos temporários "Não renovaram (últimos N dias)": só aparecem quando a
// tela de resultados leva até eles (`?grupo=<id>`).
const TEMPORARIOS = PERIODOS.map(dias =>
  grupo(grupoDosQueNaoRenovaram(dias), `NAO_RENOVARAM_${dias}`)
);
export const grupoTemporario = id =>
  TEMPORARIOS.find(item => item.id === id) ?? null;

// "Parcela atrasada" só existe com o Agger ligado: é ele quem conta a parcela.
// `temporario`: o id do grupo temporário pedido, que entra no fim da fila.
export const gruposDeSeguros = ({ aggerLigado = true, temporario = '' } = {}) =>
  [...TODOS_OS_GRUPOS, grupoTemporario(temporario)].filter(
    item => item && (aggerLigado || item.id !== GRUPO_PARCELA)
  );

// Um grupo que o endereço pode pedir: um dos de sempre ou um temporário.
export const grupoConhecido = id =>
  [...TODOS_OS_GRUPOS, ...TEMPORARIOS].some(item => item.id === id) ? id : '';

// O grupo que a lista de pessoas ganha em conta de seguros, depois de "Clientes".
export const GRUPO_DE_PESSOAS_SO_UM_SEGURO = grupo(
  GRUPO_SO_UM_SEGURO,
  'SO_UM_SEGURO'
);

const venceEmAte = dias => (seguro, agora) =>
  estaValendo(seguro, agora) && diasParaTerminar(seguro, agora) <= dias;

// Venceu nos últimos N dias e ficou com o motivo de não ter renovado.
const naoRenovouEmAte = dias => (seguro, agora) =>
  seloDoSeguro(seguro, agora) === SELOS.VENCIDO &&
  Boolean(seguro.motivo) &&
  diasDesde(seguro.termina, agora) <= dias;

const REGRAS = {
  todos: () => true,
  vence_7_dias: venceEmAte(7),
  vence_30_dias: venceEmAte(30),
  vence_90_dias: venceEmAte(90),
  em_renovacao: (seguro, agora) =>
    seloDoSeguro(seguro, agora) === SELOS.EM_RENOVACAO,
  vencido: (seguro, agora) => seloDoSeguro(seguro, agora) === SELOS.VENCIDO,
  [GRUPO_SEM_TELEFONE]: seguro => !seguro.pessoa?.phone_number,
  [GRUPO_PARCELA]: temParcelaAtrasada,
  ...Object.fromEntries(
    PERIODOS.map(dias => [grupoDosQueNaoRenovaram(dias), naoRenovouEmAte(dias)])
  ),
};

export const seguroPertenceAoGrupo = (seguro, grupoId, agora = Date.now()) => {
  const regra = REGRAS[grupoId];
  return regra ? regra(seguro, agora) : false;
};
