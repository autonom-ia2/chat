// #2897 — os grupos da aba Seguros. Cada grupo responde a uma pergunta de quem
// cuida da carteira ("quem vence esta semana?"). São os que o servidor conta
// (Carteira::Consulta): os de vencimento acumulam ("em até 30 dias" inclui quem
// vence amanhã) e só contam seguro que ainda vale. A regra de quem pertence a
// cada grupo, aqui embaixo, é a que a demonstração usa.
import {
  SELOS,
  diasParaTerminar,
  estaValendo,
  seloDoSeguro,
} from './selosDoSeguro';

export const ABA_SEGUROS = 'seguros';
export const GRUPO_PADRAO_DE_SEGUROS = 'todos';
export const GRUPO_VENCIDO = 'vencido';
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
  grupo(GRUPO_VENCIDO, 'VENCIDO'),
  grupo(GRUPO_SEM_TELEFONE, 'SEM_TELEFONE'),
];

const venceEmAte = dias => (seguro, agora) =>
  estaValendo(seguro, agora) && diasParaTerminar(seguro, agora) <= dias;

const REGRAS = {
  [GRUPO_PADRAO_DE_SEGUROS]: () => true,
  vence_7_dias: venceEmAte(7),
  vence_30_dias: venceEmAte(30),
  vence_90_dias: venceEmAte(90),
  [GRUPO_VENCIDO]: (seguro, agora) =>
    seloDoSeguro(seguro, agora) === SELOS.VENCIDO,
  [GRUPO_SEM_TELEFONE]: seguro => !seguro.pessoa?.phone_number,
};

export const seguroPertenceAoGrupo = (seguro, grupoId, agora = Date.now()) => {
  const regra = REGRAS[grupoId];
  return regra ? regra(seguro, agora) : false;
};
