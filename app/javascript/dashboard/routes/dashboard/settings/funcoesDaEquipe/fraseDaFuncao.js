import {
  CONVERSATION_PARTICIPATING_PERMISSIONS,
  CONVERSATION_UNASSIGNED_PERMISSIONS,
  CONVERSATION_VIEW_PERMISSION,
  CRM_METAS_MANAGE_PERMISSION,
  CRM_MOVE_CARDS_PERMISSION,
  SALES_VALUE_VIEW_PERMISSION,
} from 'dashboard/constants/permissions';
import {
  CONVERSATION_LEVELS,
  CRM_EXTRAS_IMPLIED_BY_ADMIN,
  LEVELS,
  MODULES,
  getLevel,
  moduleByKey,
  sensitiveExtrasOn,
} from '../customRoles/permissionMatrix';
import { valeNoServidor } from './chavesDaFuncao';
import { CRM_ADMIN, TUDO, mexeNasVendas, nivelDeVendas } from './nivelDeVendas';
import { chavesEfetivas } from './semFuncao';

// Fonte única do que uma função pode (#2308, especificação 8): a frase da lista e da prévia, o Pode e o Não pode da
// prévia, o menu e o selo de cuidado (as capacidades curtas dos cartões prontos moram em podeCurto.js). Devolve chaves
// de i18n (FUNCOES_EQUIPE.FRASE, .PODE, .MENU, .CUIDADO); quem mostra traduz.
export const nivel = (area, permissions) =>
  getLevel(moduleByKey(area), permissions);
const conversas = permissions => nivel('CONVERSATIONS', permissions);
const tem = chave => permissions => permissions.includes(chave);
export const soOlhaEMove = permissions =>
  nivelDeVendas(permissions) === LEVELS.VIEW &&
  permissions.includes(CRM_MOVE_CARDS_PERMISSION);

// Frase -------------------------------------------------------------------------------------------------------
const FRASE_DAS_CONVERSAS = {
  [CONVERSATION_LEVELS.NONE]: 'NAO_ATENDE',
  [CONVERSATION_LEVELS.VIEW]: 'SO_OLHA_CONVERSAS',
  [CONVERSATION_LEVELS.ALL]: 'TODAS',
};
const FRASE_DAS_VENDAS = {
  [LEVELS.VIEW]: 'VENDAS_SO_OLHA',
  [LEVELS.MANAGE]: 'VENDAS_MEXE',
  [TUDO]: 'VENDAS_TUDO',
};
const FRASE_DOS_CONTATOS = {
  [LEVELS.VIEW]: 'CONTATOS_SO_OLHA',
  [LEVELS.MANAGE]: 'CONTATOS_MEXE',
};

const fraseDasConversas = permissions => {
  if (conversas(permissions) !== CONVERSATION_LEVELS.LIMITED)
    return FRASE_DAS_CONVERSAS[conversas(permissions)];
  return permissions.includes(CONVERSATION_UNASSIGNED_PERMISSIONS)
    ? 'PROPRIAS_E_NOVAS'
    : 'PROPRIAS';
};

const fraseDasCampanhas = permissions => {
  if (!permissions.includes('campaign_manage')) return null;
  return permissions.includes('campaign_send')
    ? 'CAMPANHAS_DISPARA'
    : 'CAMPANHAS_CRIA';
};

// A de conversas vem em destaque; uma área sem acesso não entra no resto.
export const fraseDaFuncao = permissions => ({
  destaque: fraseDasConversas(permissions),
  resto: [
    FRASE_DAS_VENDAS[nivelDeVendas(permissions)],
    fraseDasCampanhas(permissions),
    FRASE_DOS_CONTATOS[nivel('CONTACTS', permissions)],
  ].filter(Boolean),
});

// Pode e Não pode ------------------------------------------------------------------------------------------------
// Uma frase por coisa, a mesma dos dois lados. `naoPode` diz quando a falta dela merece aparecer.
const CHAVES_DA_RECOLHIDA = [
  'report_manage',
  'desempenho_view',
  'canned_response_manage',
  'knowledge_base_manage',
  'campaign_manage',
  'campaign_send',
  'whatsapp_templates_manage',
  'meta_ads_manage',
  'inbox_manage',
  'autonomia_manage',
  'automation_manage',
  'label_manage',
  'macro_manage',
  'sla_manage',
  'insurance_manage',
  'integration_manage',
  'token_manage',
  'people_manage',
  'custom_role_manage',
  'grant_above_own',
  'financial_view',
  'financial_manage',
];

const CAPACIDADES = [
  {
    id: 'LER_E_ATENDER_TODAS',
    tem: p => conversas(p) === CONVERSATION_LEVELS.ALL,
  },
  {
    id: 'RESPONDER_ENTREGUES',
    tem: p => conversas(p) === CONVERSATION_LEVELS.LIMITED,
    naoPode: p => conversas(p) === CONVERSATION_LEVELS.VIEW,
  },
  {
    id: 'PEGAR_NOVAS',
    tem: p =>
      conversas(p) === CONVERSATION_LEVELS.LIMITED &&
      p.includes(CONVERSATION_UNASSIGNED_PERMISSIONS),
  },
  {
    id: 'AJUDAR_PELO_LINK',
    tem: p =>
      conversas(p) === CONVERSATION_LEVELS.LIMITED &&
      p.includes(CONVERSATION_PARTICIPATING_PERMISSIONS),
  },
  {
    id: 'LER_COLEGAS',
    tem: tem(CONVERSATION_VIEW_PERMISSION),
    naoPode: p => conversas(p) === CONVERSATION_LEVELS.LIMITED,
  },
  {
    id: 'ATENDER_CONVERSAS',
    tem: () => false,
    naoPode: p => conversas(p) === CONVERSATION_LEVELS.NONE,
  },
  { id: 'APAGAR_MENSAGENS', tem: tem('conversation_message_delete') },
  { id: 'QUEM_RECEBE', tem: tem('assignment_manage') },
  {
    id: 'CRIAR_MOVER_VENDAS',
    tem: mexeNasVendas,
    naoPode: p => nivelDeVendas(p) === LEVELS.VIEW && !soOlhaEMove(p),
  },
  // Função antiga "Só olha" com mover as vendas (gravada pela tela de antes): o servidor deixa mover
  // (CardPolicy#move?), e a prévia diz isso em vez de "Não pode criar e mover".
  { id: 'MOVER_VENDAS', tem: p => soOlhaEMove(p) },
  { id: 'ARQUIVAR_VENDAS', tem: tem('crm_delete_cards') },
  { id: 'MONTAR_COLUNAS', tem: tem('crm_manage_pipelines') },
  { id: 'RELATORIOS_DAS_VENDAS', tem: tem('crm_view_reports') },
  { id: 'VALORES_EM_RS', tem: tem(SALES_VALUE_VIEW_PERMISSION) },
  // Metas sem R$ ficam inertes no servidor (MetasPolicy#manage?): a prévia não as promete (decisão 14A).
  {
    id: 'METAS_DO_MES',
    tem: p =>
      p.includes(CRM_METAS_MANAGE_PERMISSION) &&
      valeNoServidor(CRM_METAS_MANAGE_PERMISSION, p),
  },
  { id: 'EXPORTAR_VENDAS', tem: tem('crm_export') },
  { id: 'IA_NAS_VENDAS', tem: tem('crm_manage_ai') },
  { id: 'PROCURAR_CLIENTES', tem: tem('prospecting_manage') },
  { id: 'BUSCAS_DE_TODOS', tem: tem('prospecting_view_all_searches') },
  { id: 'AGENDA', tem: tem('agendamento_manage') },
  {
    id: 'MUDAR_CONTATOS',
    tem: tem('contact_manage'),
    naoPode: p => nivel('CONTACTS', p) === LEVELS.VIEW,
  },
  {
    id: 'EXPORTAR_CONTATOS',
    tem: tem('contact_export'),
    naoPode: p => nivel('CONTACTS', p) !== LEVELS.NONE,
  },
  { id: 'APAGAR_CONTATOS', tem: tem('contact_delete') },
  { id: 'CAMPOS_EXTRAS', tem: tem('attribute_manage') },
  ...CHAVES_DA_RECOLHIDA.map(chave => ({
    id: chave.toUpperCase(),
    tem: tem(chave),
  })),
];

export const podeDaFuncao = permissions =>
  CAPACIDADES.filter(item => item.tem(permissions)).map(item => item.id);

export const naoPodeDaFuncao = permissions =>
  CAPACIDADES.filter(
    item => item.naoPode?.(permissions) && !item.tem(permissions)
  ).map(item => item.id);

// Menu -----------------------------------------------------------------------------------------------------------
const MENU = [
  ['CONVERSATIONS', 'CONVERSAS'],
  ['CONTACTS', 'CONTATOS'],
  ['CRM', 'VENDAS'],
  ['PROSPECTING', 'CLIENTES_NOVOS'],
  ['CAMPAIGNS', 'CAMPANHAS'],
  ['META_ADS', 'ANUNCIOS'],
  ['AUTONOMIA', 'ROBOS'],
  ['INSURANCE', 'COTACOES'],
  ['REPORTS', 'RELATORIOS'],
  ['DESEMPENHO', 'RELATORIOS'],
  ['KNOWLEDGE_BASE', 'CENTRAL_DE_AJUDA'],
];
const DO_MENU = new Set(MENU.map(([area]) => area));
// O nome com que a área aparece no menu (FUNCOES_EQUIPE.MENU), ou null para a que mora em Configurações.
export const itemDoMenu = area =>
  MENU.find(([chave]) => chave === area)?.[1] || null;

export const menuDaFuncao = permissions => {
  const comAcesso = area => nivel(area, permissions) !== LEVELS.NONE;
  const itens = MENU.filter(([area]) => comAcesso(area)).map(
    ([, item]) => item
  );
  const configuracoes = MODULES.some(
    module => !DO_MENU.has(module.key) && comAcesso(module.key)
  );
  return [...new Set(itens), ...(configuracoes ? ['CONFIGURACOES'] : [])];
};

// Selo -----------------------------------------------------------------------------------------------------------
// As ações que pedem cuidado que a função tem hoje (FUNCOES_EQUIPE.CUIDADO), na ordem da tela. Com crm_admin, as
// seis que ele inclui já cabem em "cuidar de tudo nas vendas". Uma chave sem a dependência (metas sem R$) não vale
// no servidor e não entra.
const ORDEM_DO_SELO = [
  CRM_ADMIN,
  'campaign_send',
  'contact_export',
  'contact_delete',
  'conversation_message_delete',
  'crm_export',
  CRM_METAS_MANAGE_PERMISSION,
  SALES_VALUE_VIEW_PERMISSION,
  'crm_manage_ai',
  'custom_role_manage',
  'grant_above_own',
];
export const cuidadosDaFuncao = permissions => {
  const doAdmin = permissions.includes(CRM_ADMIN)
    ? CRM_EXTRAS_IMPLIED_BY_ADMIN
    : [];
  const ligadas = sensitiveExtrasOn(permissions).filter(
    chave => !doAdmin.includes(chave) && valeNoServidor(chave, permissions)
  );
  return ORDEM_DO_SELO.filter(chave => ligadas.includes(chave));
};

// Prévia estável -------------------------------------------------------------------------------------------------
// O Pode e o Não pode contam o que a função dá de fato (chavesEfetivas), a mesma leitura do Cuidado e da Perda de
// acesso: uma função antiga com crm_admin sem as seis gravadas mostra tudo o que o servidor dá.
export const previaDaFuncao = permissions => {
  const efetivas = chavesEfetivas(permissions);
  return {
    frase: fraseDaFuncao(permissions),
    pode: podeDaFuncao(efetivas),
    naoPode: naoPodeDaFuncao(efetivas),
    menu: menuDaFuncao(permissions),
  };
};

// Pode e Não pode fotografados ao abrir: o Pode mantém a ordem da foto e o novo entra no fim, marcado; o Não pode
// só perde o que mudou de lado (ou deixou de valer) e só ganha o que saiu do Pode, sem marca.
export const mesclarPrevia = (foto, atual) => ({
  ...atual,
  pode: [
    ...foto.pode
      .filter(id => atual.pode.includes(id))
      .map(id => ({ id, novo: false })),
    ...atual.pode
      .filter(id => !foto.pode.includes(id))
      .map(id => ({ id, novo: true })),
  ],
  naoPode: [
    ...foto.naoPode.filter(id => atual.naoPode.includes(id)),
    ...atual.naoPode.filter(
      id => foto.pode.includes(id) && !foto.naoPode.includes(id)
    ),
  ],
});
