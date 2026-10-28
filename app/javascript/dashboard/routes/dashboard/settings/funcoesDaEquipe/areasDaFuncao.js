import {
  CONVERSATION_LEVELS,
  LEVELS,
  getLevel,
  levelOptions,
  moduleByKey,
  setLevel,
} from '../customRoles/permissionMatrix';
import { reachesKeys } from 'dashboard/helper/peopleAccess';
import { comImplicadas } from './comImplicadas';
import { motivoDasChaves, motivoDaTrava } from './motivoDaTrava';

// O mapa fechado das áreas e chaves (#2308, especificação 6): onde cada um dos 24 módulos e cada uma das 57 chaves
// aparece na conversa guiada. Os specs conferem 24/24 e 57/57.
export const LINHAS = ['CONVERSATIONS', 'CONTACTS', 'CRM'];
export const DENTRO_DE = {
  ASSIGNMENT: 'CONVERSATIONS',
  ATTRIBUTES: 'CONTACTS',
  PROSPECTING: 'CRM',
  SCHEDULING: 'CRM',
};
export const RECOLHIDA = [
  'REPORTS',
  'DESEMPENHO',
  'CANNED_RESPONSES',
  'KNOWLEDGE_BASE',
  'CAMPAIGNS',
  'WHATSAPP_TEMPLATES',
  'META_ADS',
  'INBOXES',
  'AUTONOMIA',
  'AUTOMATIONS',
  'LABELS',
  'MACROS',
  'SLA',
];
// Cotações: só na conta com Cotação ou quando a função já tem a chave (decisão 13).
export const CONDICIONAL = ['INSURANCE'];
// Para quem não é administrador, ficam com cadeado (as chaves são de delegação).
export const SO_ADMIN = ['INTEGRATIONS', 'PEOPLE', 'FINANCE'];

export const DONO_DAS_CHAVES = {
  CONVERSAS: ['conversation_view', 'conversation_manage'],
  CONVERSAS_SUBESCOLHAS: [
    'conversation_unassigned_manage',
    'conversation_participating_manage',
  ],
  CONVERSAS_RECOLHIDA: ['assignment_manage'],
  CUIDADO: [
    'conversation_message_delete',
    'contact_export',
    'contact_delete',
    'campaign_send',
    'crm_export',
    'crm_metas_manage',
    'crm_manage_ai',
  ],
  CONTATOS: ['contact_view', 'contact_manage', 'attribute_manage'],
  VENDAS: ['crm_view', 'crm_manage_cards', 'crm_move_cards', 'crm_admin'],
  VENDAS_MAIS: [
    'crm_delete_cards',
    'crm_manage_pipelines',
    'crm_view_reports',
    'sales_value_view',
    'prospecting_view',
    'prospecting_manage',
    'prospecting_view_all_searches',
    'agendamento_view',
    'agendamento_manage',
  ],
  RECOLHIDA: [
    'report_manage',
    'desempenho_view',
    'canned_response_manage',
    'knowledge_base_view',
    'knowledge_base_manage',
    'campaign_view',
    'campaign_manage',
    'whatsapp_templates_view',
    'whatsapp_templates_manage',
    'meta_ads_view',
    'meta_ads_manage',
    'inbox_view',
    'inbox_manage',
    'autonomia_view',
    'autonomia_manage',
    'automation_view',
    'automation_manage',
    'label_manage',
    'macro_manage',
    'sla_manage',
  ],
  COTACOES: ['insurance_view', 'insurance_manage'],
  CADEADO: [
    'integration_manage',
    'token_manage',
    'people_manage',
    'custom_role_manage',
    'grant_above_own',
    'financial_view',
    'financial_manage',
  ],
};

// Níveis e travas ------------------------------------------------------------------------------------------------
const ATENDE = [CONVERSATION_LEVELS.LIMITED, CONVERSATION_LEVELS.ALL];

export const emManage = (module, permissions) =>
  module.type === 'conversations'
    ? ATENDE.includes(getLevel(module, permissions))
    : getLevel(module, permissions) === LEVELS.MANAGE;

// Um nível nunca grava chave travada: a trava do nível é a das chaves que ele grava sozinho.
export const travaDoNivel = (giver, module, nivel) =>
  nivel === LEVELS.NONE
    ? null
    : motivoDasChaves(giver, setLevel(module, nivel, []));

// Área inteira fora do alcance: todo nível acima de "Não vê" travado.
export const areaTravada = (giver, module) =>
  levelOptions(module)
    .filter(nivel => nivel !== LEVELS.NONE)
    .every(nivel => travaDoNivel(giver, module, nivel));

// Recolhida de Ajustes -------------------------------------------------------------------------------------------
// Separa as áreas da recolhida: as que mudaram desde o começo sobem para a lista de cima; as travadas e desligadas
// vão para o cadeado; o resto fica na recolhida, na ordem fixa.
export const areasDaRecolhida = ({
  giver,
  permissions,
  inicial,
  comCotacoes,
}) => {
  const candidatas = [
    ...RECOLHIDA,
    ...(comCotacoes ? CONDICIONAL : []),
    ...SO_ADMIN,
  ].map(moduleByKey);
  const mudou = module =>
    getLevel(module, permissions) !== getLevel(module, inicial);
  const noCadeado = module =>
    getLevel(module, permissions) === LEVELS.NONE && areaTravada(giver, module);
  return {
    subiram: candidatas.filter(mudou),
    recolhidas: candidatas.filter(m => !mudou(m) && !noCadeado(m)),
    cadeado: candidatas.filter(m => !mudou(m) && noCadeado(m)),
  };
};

// Título: as duas primeiras + "e mais N áreas". Estado: o que olha e o que mexe hoje.
export const resumoDaRecolhida = (recolhidas, permissions) => ({
  primeiras: recolhidas.slice(0, 2).map(module => module.key),
  mais: Math.max(recolhidas.length - 2, 0),
  olha: recolhidas
    .filter(module => getLevel(module, permissions) === LEVELS.VIEW)
    .map(module => module.key),
  mexe: recolhidas
    .filter(module => getLevel(module, permissions) === LEVELS.MANAGE)
    .map(module => module.key),
});

// Cuidado em três grupos -----------------------------------------------------------------------------------------
const CUIDADO = [
  { chave: 'contact_export', area: 'CONTACTS' },
  { chave: 'conversation_message_delete', area: 'CONVERSATIONS' },
  { chave: 'crm_manage_ai', area: 'CRM' },
  { chave: 'contact_delete', area: 'CONTACTS' },
  { chave: 'campaign_send', area: 'CAMPAIGNS' },
  { chave: 'crm_export', area: 'CRM' },
  { chave: 'crm_metas_manage', area: 'CRM' },
];

const precisaDeManage = (module, chave) =>
  (module.manageOnlyExtras || []).includes(chave);

// (b) liga junto com a área: só vale com a área em manage, que hoje não está, e quem dá alcança as duas.
const ligaJunto = (giver, item, permissions) => {
  const module = moduleByKey(item.area);
  if (!precisaDeManage(module, item.chave) || emManage(module, permissions))
    return false;
  const comArea = [...permissions, module.levels.manage, item.chave];
  return reachesKeys(giver, comImplicadas(comArea));
};

// (a) liga agora: quem dá alcança a chave, e a área já está em manage (ou a chave não depende disso).
const ligaAgora = (giver, item, permissions) => {
  const module = moduleByKey(item.area);
  if (motivoDaTrava(giver, item.chave)) return false;
  return emManage(module, permissions) || !precisaDeManage(module, item.chave);
};

const motivoDoCuidado = (giver, item) => {
  const module = moduleByKey(item.area);
  const comArea = precisaDeManage(module, item.chave)
    ? [item.chave, module.levels.manage]
    : [item.chave];
  return motivoDasChaves(giver, comArea) || motivoDaTrava(giver, item.chave);
};

// Ordem de teste: (b) antes de (a), e (c) o resto. Apagar mensagens só existe para quem atende conversas.
const grupoDe = (giver, item, permissions) => {
  if (ligaJunto(giver, item, permissions)) return 'ligaJunto';
  if (ligaAgora(giver, item, permissions)) return 'ligaAgora';
  return 'naoPode';
};

export const gruposDoCuidado = (giver, permissions) => {
  const atende = emManage(moduleByKey('CONVERSATIONS'), permissions);
  const itens = CUIDADO.filter(
    item => atende || item.chave !== 'conversation_message_delete'
  ).map(item => ({ ...item, grupo: grupoDe(giver, item, permissions) }));
  const doGrupo = grupo => itens.filter(item => item.grupo === grupo);
  return {
    ligaJunto: doGrupo('ligaJunto'),
    ligaAgora: doGrupo('ligaAgora'),
    naoPode: doGrupo('naoPode').map(item => ({
      ...item,
      motivo: motivoDoCuidado(giver, item),
    })),
  };
};
