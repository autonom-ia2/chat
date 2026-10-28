import {
  CONVERSATION_LEVELS,
  CRM_EXTRAS_IMPLIED_BY_ADMIN,
  LEVELS,
  getLevel,
  moduleByKey,
  sensitiveExtrasOn,
} from '../customRoles/permissionMatrix';

// A frase curta do cartão da lista (#2308): só as três áreas fixas (conversas, vendas e contatos), lidas do
// nível que a função grava. A frase completa, com todas as áreas, é o fraseDaFuncao do PR 3.
const CONVERSATION_UNASSIGNED = 'conversation_unassigned_manage';
const CRM_ADMIN = 'crm_admin';

const FRASE_DAS_CONVERSAS = {
  [CONVERSATION_LEVELS.NONE]: 'NAO_ATENDE',
  [CONVERSATION_LEVELS.VIEW]: 'SO_OLHA_CONVERSAS',
  [CONVERSATION_LEVELS.LIMITED]: 'PROPRIAS',
  [CONVERSATION_LEVELS.ALL]: 'TODAS',
};
const FRASE_DAS_VENDAS = {
  [LEVELS.VIEW]: 'VENDAS_SO_OLHA',
  [LEVELS.MANAGE]: 'VENDAS_MEXE',
};
const FRASE_DOS_CONTATOS = {
  [LEVELS.VIEW]: 'CONTATOS_SO_OLHA',
  [LEVELS.MANAGE]: 'CONTATOS_MEXE',
};

const fraseDasConversas = permissions => {
  const nivel = getLevel(moduleByKey('CONVERSATIONS'), permissions);
  const pegaAsNovas =
    nivel === CONVERSATION_LEVELS.LIMITED &&
    permissions.includes(CONVERSATION_UNASSIGNED);
  return pegaAsNovas ? 'PROPRIAS_E_NOVAS' : FRASE_DAS_CONVERSAS[nivel];
};

const fraseDasVendas = permissions =>
  permissions.includes(CRM_ADMIN)
    ? 'VENDAS_TUDO'
    : FRASE_DAS_VENDAS[getLevel(moduleByKey('CRM'), permissions)];

// Chaves de FUNCOES_EQUIPE.FRASE: a de conversas vem em destaque; uma área sem acesso não entra no resto.
export const fraseDoCartao = permissions => ({
  destaque: fraseDasConversas(permissions),
  resto: [
    fraseDasVendas(permissions),
    FRASE_DOS_CONTATOS[getLevel(moduleByKey('CONTACTS'), permissions)],
  ].filter(Boolean),
});

// O selo mostra as ações que pedem cuidado que a função tem hoje (chaves de FUNCOES_EQUIPE.CUIDADO). Com
// crm_admin, as seis que ele inclui já cabem em "cuidar de tudo nas vendas".
export const cuidadosDaFuncao = permissions => {
  const ligadas = sensitiveExtrasOn(permissions);
  if (!permissions.includes(CRM_ADMIN)) return ligadas;
  return ligadas.filter(chave => !CRM_EXTRAS_IMPLIED_BY_ADMIN.includes(chave));
};
