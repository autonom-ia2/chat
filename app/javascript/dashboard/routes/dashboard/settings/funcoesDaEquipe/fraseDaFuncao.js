import {
  CONVERSATION_LEVELS,
  CRM_EXTRAS_IMPLIED_BY_ADMIN,
  LEVELS,
  MODULES,
  getLevel,
  moduleByKey,
  sensitiveExtrasOn,
} from '../customRoles/permissionMatrix';
import { TUDO, nivelDeVendas } from './nivelDeVendas';

// Fonte única do que uma função pode (#2308, especificação 8): a frase da lista e da prévia, o Pode e o Não pode da
// prévia, as capacidades curtas dos cartões prontos (podeCurto), o menu e o selo de cuidado. Devolve chaves de i18n
// (FUNCOES_EQUIPE.FRASE, .PODE, .CURTO, .MENU, .CUIDADO); quem mostra traduz.
const nivel = (area, permissions) => getLevel(moduleByKey(area), permissions);
const conversas = permissions => nivel('CONVERSATIONS', permissions);
const mexeNasVendas = permissions =>
  [LEVELS.MANAGE, TUDO].includes(nivelDeVendas(permissions));
const tem = chave => permissions => permissions.includes(chave);

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
  return permissions.includes('conversation_unassigned_manage')
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
      p.includes('conversation_unassigned_manage'),
  },
  {
    id: 'AJUDAR_PELO_LINK',
    tem: p =>
      conversas(p) === CONVERSATION_LEVELS.LIMITED &&
      p.includes('conversation_participating_manage'),
  },
  {
    id: 'LER_COLEGAS',
    tem: tem('conversation_view'),
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
    naoPode: p => nivelDeVendas(p) === LEVELS.VIEW,
  },
  { id: 'ARQUIVAR_VENDAS', tem: tem('crm_delete_cards') },
  { id: 'MONTAR_COLUNAS', tem: tem('crm_manage_pipelines') },
  { id: 'RELATORIOS_DAS_VENDAS', tem: tem('crm_view_reports') },
  { id: 'VALORES_EM_RS', tem: tem('sales_value_view') },
  // Metas sem R$ ficam inertes no servidor (MetasPolicy#manage?): a prévia não as promete (decisão 14A).
  {
    id: 'METAS_DO_MES',
    tem: p => p.includes('crm_metas_manage') && p.includes('sales_value_view'),
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

// Capacidades curtas dos cartões prontos -------------------------------------------------------------------------
const curto = (chave, tipo = 'pode') => ({ chave, tipo });
const mexe = (area, permissions) => nivel(area, permissions) === LEVELS.MANAGE;

const CONVERSA_CURTA = {
  [CONVERSATION_LEVELS.ALL]: curto('TODAS'),
  [CONVERSATION_LEVELS.LIMITED]: curto('PROPRIAS'),
  [CONVERSATION_LEVELS.VIEW]: curto('SO_OLHA_CONVERSAS', 'soOlha'),
};

const campanhas = p => {
  if (!p.includes('campaign_manage')) return null;
  return curto(p.includes('campaign_send') ? 'CAMPANHAS_DISPARA' : 'CAMPANHAS');
};
const vendas = p => {
  if (!mexeNasVendas(p)) return null;
  if (p.includes('crm_manage_pipelines')) return curto('VENDAS_E_COLUNAS');
  return curto(mexe('CONTACTS', p) ? 'CONTATOS_E_VENDAS' : 'VENDAS');
};
const arruma = p =>
  ['inbox_manage', 'autonomia_manage', 'automation_manage'].every(chave =>
    p.includes(chave)
  )
    ? curto('ARRUMA')
    : null;
// Quem mexe nas vendas já falou dos contatos nelas (ou trocou pelas colunas, mais próprias da função).
const contatos = p => {
  if (mexe('CONTACTS', p)) return mexeNasVendas(p) ? null : curto('CONTATOS');
  return nivel('CONTACTS', p) === LEVELS.VIEW
    ? curto('SO_OLHA_CONTATOS', 'soOlha')
    : null;
};
const relatorios = p =>
  p.includes('report_manage') || p.includes('crm_view_reports')
    ? curto('RELATORIOS')
    : null;
const procura = p =>
  p.includes('prospecting_manage') ? curto('PROCURA') : null;

const AREAS_QUE_SO_OLHA = ['CONTACTS', 'CRM', 'CAMPAIGNS', 'REPORTS'];
const soOlha = p =>
  !MODULES.some(module => mexe(module.key, p)) &&
  !mexeNasVendas(p) &&
  ![CONVERSATION_LEVELS.LIMITED, CONVERSATION_LEVELS.ALL].includes(
    nivel('CONVERSATIONS', p)
  );

const positivas = p => {
  if (soOlha(p)) {
    const areas = AREAS_QUE_SO_OLHA.filter(
      area => nivel(area, p) !== LEVELS.NONE
    );
    return areas.length ? [{ ...curto('SO_OLHA_AREAS', 'soOlha'), areas }] : [];
  }
  return [
    CONVERSA_CURTA[nivel('CONVERSATIONS', p)],
    campanhas(p),
    vendas(p),
    arruma(p),
    contatos(p),
    relatorios(p),
    procura(p),
  ].filter(Boolean);
};

// Até 3, com tipo (pode | soOlha | naoFaz) para o ícone. "Não atende conversas" sempre entra, por último.
export const podeCurto = permissions => {
  const naoAtende =
    nivel('CONVERSATIONS', permissions) === CONVERSATION_LEVELS.NONE
      ? [curto('NAO_ATENDE', 'naoFaz')]
      : [];
  return [
    ...positivas(permissions).slice(0, 3 - naoAtende.length),
    ...naoAtende,
  ];
};

// Selo -----------------------------------------------------------------------------------------------------------
// As ações que pedem cuidado que a função tem hoje (FUNCOES_EQUIPE.CUIDADO), na ordem da tela. Com crm_admin, as
// seis que ele inclui já cabem em "cuidar de tudo nas vendas".
const ORDEM_DO_SELO = [
  'crm_admin',
  'campaign_send',
  'contact_export',
  'contact_delete',
  'conversation_message_delete',
  'crm_export',
  'crm_metas_manage',
  'sales_value_view',
  'crm_manage_ai',
  'custom_role_manage',
  'grant_above_own',
];
export const cuidadosDaFuncao = permissions => {
  const ligadas = new Set(sensitiveExtrasOn(permissions));
  if (permissions.includes('crm_admin'))
    CRM_EXTRAS_IMPLIED_BY_ADMIN.forEach(chave => ligadas.delete(chave));
  return ORDEM_DO_SELO.filter(chave => ligadas.has(chave));
};

// Prévia estável -------------------------------------------------------------------------------------------------
export const previaDaFuncao = permissions => ({
  frase: fraseDaFuncao(permissions),
  pode: podeDaFuncao(permissions),
  naoPode: naoPodeDaFuncao(permissions),
  menu: menuDaFuncao(permissions),
});

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
