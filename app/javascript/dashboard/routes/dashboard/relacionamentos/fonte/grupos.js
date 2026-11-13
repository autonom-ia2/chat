// #2894 — os grupos da lista de Relacionamentos. Cada grupo responde a uma
// pergunta da pessoa ("quem sumiu?"), não é um filtro. Só a regra: a tela e a
// fonte (demonstração ou API) usam as mesmas funções.
export const DIA_EM_MS = 24 * 60 * 60 * 1000;
export const LIMITE_FALOU_HA_POUCO_DIAS = 30;
export const LIMITE_SUMIU_DIAS = 90;

export const ABAS = { PESSOAS: 'pessoas', EMPRESAS: 'empresas' };

const grupo = (id, chave) => ({
  id,
  nome: `RELACIONAMENTOS.GRUPOS.${chave}.NOME`,
  explicacao: `RELACIONAMENTOS.GRUPOS.${chave}.EXPLICACAO`,
});

export const GRUPOS_DE_PESSOAS = [
  grupo('todos', 'TODOS'),
  grupo('clientes', 'CLIENTES'),
  grupo('falou_ha_pouco', 'FALOU_HA_POUCO'),
  grupo('sumiu_1_a_3_meses', 'SUMIU_1_A_3_MESES'),
  grupo('sumiu_mais_de_3_meses', 'SUMIU_MAIS_DE_3_MESES'),
  grupo('nunca_conversou', 'NUNCA_CONVERSOU'),
  grupo('nao_quer_mensagens', 'NAO_QUER_MENSAGENS'),
];

export const GRUPOS_DE_EMPRESAS = [
  grupo('todas', 'EMPRESAS_TODAS'),
  grupo('com_clientes', 'EMPRESAS_COM_CLIENTES'),
  grupo('sem_pessoas', 'EMPRESAS_SEM_PESSOAS'),
  grupo('sem_conversa_3_meses', 'EMPRESAS_SEM_CONVERSA_3_MESES'),
];

export const GRUPO_PADRAO = {
  [ABAS.PESSOAS]: 'todos',
  [ABAS.EMPRESAS]: 'todas',
};

// #2897 — na conta que tem a carteira de seguros a lista de pessoas ganha um
// grupo, logo depois de "Clientes": quem tem só um seguro ativo. Quem diz
// quem pertence é o servidor (Carteira::NaListaDePessoas); na demonstração, a
// carteira fictícia (demo/carteiraNaLista.js). O nome mora no catálogo da
// carteira.
export const GRUPO_SO_UM_SEGURO = 'so_um_seguro';
const SO_UM_SEGURO = {
  id: GRUPO_SO_UM_SEGURO,
  nome: 'RELACIONAMENTOS_CARTEIRA.PESSOAS.SO_UM_SEGURO.NOME',
  explicacao: 'RELACIONAMENTOS_CARTEIRA.PESSOAS.SO_UM_SEGURO.EXPLICACAO',
};
const GRUPO_ANTES_DO_DE_SEGUROS = 'clientes';
const GRUPOS_DE_PESSOAS_COM_SEGUROS = GRUPOS_DE_PESSOAS.flatMap(item =>
  item.id === GRUPO_ANTES_DO_DE_SEGUROS ? [item, SO_UM_SEGURO] : [item]
);

// `comSeguros`: a conta tem a carteira de seguros.
export const gruposDaAba = (aba, { comSeguros = false } = {}) => {
  if (aba === ABAS.EMPRESAS) return GRUPOS_DE_EMPRESAS;
  return comSeguros ? GRUPOS_DE_PESSOAS_COM_SEGUROS : GRUPOS_DE_PESSOAS;
};

// Dias desde a última conversa; null quando nunca houve. A data vem em segundos
// (como a API de contatos devolve).
const diasSemConversa = (ultimaEmSegundos, agora) =>
  ultimaEmSegundos === null || ultimaEmSegundos === undefined
    ? null
    : (agora - ultimaEmSegundos * 1000) / DIA_EM_MS;

const conversouAte = (dias, limite) => dias !== null && dias <= limite;

const REGRAS_DE_PESSOA = {
  todos: () => true,
  clientes: pessoa => pessoa.contact_type === 'customer',
  falou_ha_pouco: (pessoa, dias) =>
    conversouAte(dias, LIMITE_FALOU_HA_POUCO_DIAS),
  sumiu_1_a_3_meses: (pessoa, dias) =>
    dias !== null &&
    dias > LIMITE_FALOU_HA_POUCO_DIAS &&
    dias <= LIMITE_SUMIU_DIAS,
  sumiu_mais_de_3_meses: (pessoa, dias) =>
    dias !== null && dias > LIMITE_SUMIU_DIAS,
  nunca_conversou: (pessoa, dias) => dias === null,
  nao_quer_mensagens: pessoa => Boolean(pessoa.opted_out_at),
};

const REGRAS_DE_EMPRESA = {
  todas: () => true,
  com_clientes: empresa => empresa.customers_count > 0,
  sem_pessoas: empresa => empresa.contacts_count === 0,
  sem_conversa_3_meses: (empresa, dias) =>
    dias === null || dias > LIMITE_SUMIU_DIAS,
};

export const pertenceAoGrupo = (pessoa, grupoId, agora = Date.now()) => {
  const regra = REGRAS_DE_PESSOA[grupoId];
  return regra
    ? regra(pessoa, diasSemConversa(pessoa.last_activity_at, agora))
    : false;
};

export const empresaPertenceAoGrupo = (
  empresa,
  grupoId,
  agora = Date.now()
) => {
  const regra = REGRAS_DE_EMPRESA[grupoId];
  return regra
    ? regra(empresa, diasSemConversa(empresa.last_activity_at, agora))
    : false;
};
