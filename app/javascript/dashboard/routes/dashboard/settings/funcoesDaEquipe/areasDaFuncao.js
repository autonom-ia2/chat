import {
  CONVERSATION_LEVELS,
  KEYS_OUTSIDE_MATRIX,
  LEVELS,
  getLevel,
  isExtraLocked,
  levelOptions,
  moduleByKey,
  setLevel,
} from '../customRoles/permissionMatrix';
import { reachesKeys } from 'dashboard/helper/peopleAccess';
import {
  ALCANCES_DE_CONVERSA,
  dependenciaDe,
  valeNoServidor,
} from './chavesDaFuncao';
import { comImplicadas } from './comImplicadas';
import { motivoDasChaves, motivoDaTrava } from './motivoDaTrava';

// O mapa fechado das áreas e chaves (#2308, especificação 6): onde cada um dos 24 módulos e cada uma das 59 chaves
// aparece na conversa guiada. Os specs conferem 24/24 e 59/59; as chaves que nenhuma tela mostra ficam em FORA (#2352).
export const LINHAS = ['CONVERSATIONS', 'CONTACTS', 'CRM'];
export const DENTRO_DE = {
  ASSIGNMENT: 'CONVERSATIONS',
  ATTRIBUTES: 'CONTACTS',
  PROSPECTING: 'CRM',
  SCHEDULING: 'CRM',
};
// As áreas que moram dentro de uma linha de Ajustes, na ordem do mapa: as perguntas leem daqui.
export const areasDentroDe = linha =>
  Object.keys(DENTRO_DE)
    .filter(area => DENTRO_DE[area] === linha)
    .map(moduleByKey);
export const RECOLHIDA = [
  'REPORTS',
  'DESEMPENHO',
  'CANNED_RESPONSES',
  'CAMPAIGNS',
  'WHATSAPP_TEMPLATES',
  'META_ADS',
  'POSTS',
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
    'campaign_view',
    'campaign_manage',
    'whatsapp_templates_view',
    'whatsapp_templates_manage',
    'meta_ads_view',
    'meta_ads_manage',
    'posts_view',
    'posts_manage',
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
  FORA: KEYS_OUTSIDE_MATRIX,
};

// Níveis e travas ------------------------------------------------------------------------------------------------
const ATENDE = [CONVERSATION_LEVELS.LIMITED, CONVERSATION_LEVELS.ALL];

export const emManage = (module, permissions) =>
  module.type === 'conversations'
    ? ATENDE.includes(getLevel(module, permissions))
    : getLevel(module, permissions) === LEVELS.MANAGE;

// "Atende as próprias" grava um alcance, e o setLevel começa pelas conversas de que a pessoa participa. Quem dá sem
// esse alcance, mas com o das novas sem ninguém, dá as próprias por ele: o servidor confere chave a chave
// (GrantGuard#reach?), e um alcance basta (toggleExtra). Sem isso, as próprias ficavam com cadeado para quem só tem
// conversation_unassigned_manage (#2403). Um alcance que a função já tinha não sai.
const [ALCANCE_DAS_NOVAS, ALCANCE_DE_QUEM_PARTICIPA] = ALCANCES_DE_CONVERSA;
const pelasNovas = (giver, antes, chaves) =>
  chaves.includes(ALCANCE_DE_QUEM_PARTICIPA) &&
  !antes.includes(ALCANCE_DE_QUEM_PARTICIPA) &&
  !reachesKeys(giver, [ALCANCE_DE_QUEM_PARTICIPA]) &&
  reachesKeys(giver, [ALCANCE_DAS_NOVAS]);

export const nivelar = (giver, module, nivel, permissions) => {
  const chaves = setLevel(module, nivel, permissions);
  if (module.type !== 'conversations' || nivel !== CONVERSATION_LEVELS.LIMITED)
    return chaves;
  if (!pelasNovas(giver, permissions, chaves)) return chaves;
  return [
    ...new Set([
      ...chaves.filter(chave => chave !== ALCANCE_DE_QUEM_PARTICIPA),
      ALCANCE_DAS_NOVAS,
    ]),
  ];
};

// Um nível nunca grava chave travada: a trava do nível é a das chaves que ele grava sozinho.
export const travaDoNivel = (giver, module, nivel) =>
  nivel === LEVELS.NONE
    ? null
    : motivoDasChaves(giver, nivelar(giver, module, nivel, []));

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
export const CUIDADO = [
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

// O que entra junto ao ligar uma (b): a chave de que ela depende (as metas trazem o R$, KEY_DEPENDENCIES) ou, sem
// dependência, a área em manage (apagar contatos, disparar campanhas).
export const juntoCom = item => {
  const dependencia = dependenciaDe(item.chave);
  return dependencia ? [dependencia] : [moduleByKey(item.area).levels.manage];
};

// Falta o que (b) liga junto: a dependência desligada, ou a área (de uma chave que só vale com ela em manage) fora de
// manage.
const faltaOJunto = (item, permissions) => {
  if (dependenciaDe(item.chave))
    return !valeNoServidor(item.chave, permissions);
  const module = moduleByKey(item.area);
  return precisaDeManage(module, item.chave) && !emManage(module, permissions);
};

// (b) liga junto: falta o que ela precisa, e quem dá alcança as duas coisas.
export const ligaJunto = (giver, item, permissions) =>
  faltaOJunto(item, permissions) &&
  reachesKeys(
    giver,
    comImplicadas([...permissions, ...juntoCom(item), item.chave])
  );

// (a) liga agora: quem dá alcança a chave, e nada falta. É a negação exata de faltaOJunto: os dois nunca valem
// juntos, e a ordem de teste de grupoDe é só a da especificação.
export const ligaAgora = (giver, item, permissions) =>
  !motivoDaTrava(giver, item.chave) && !faltaOJunto(item, permissions);

// O motivo nunca fica vazio: quem dá alcança a chave e a área, mas não o resto da função com elas (ligaJunto confere
// a função inteira), e o motivo é o dessa função inteira.
const motivoDoCuidado = (giver, item, permissions) => {
  const module = moduleByKey(item.area);
  const comArea = precisaDeManage(module, item.chave)
    ? [item.chave, module.levels.manage]
    : [item.chave];
  return (
    motivoDasChaves(giver, comArea) ||
    motivoDasChaves(giver, [...permissions, ...juntoCom(item), item.chave])
  );
};

// Ordem de teste: (b) antes de (a), e (c) o resto.
const grupoDe = (giver, item, permissions) => {
  if (ligaJunto(giver, item, permissions)) return 'ligaJunto';
  if (ligaAgora(giver, item, permissions)) return 'ligaAgora';
  return 'naoPode';
};

// Quando uma linha aparece: apagar mensagens só para quem atende; uma chave que não depende de mexer na área só
// com a área à vista (senão ficaria inerte, como levar a planilha de contatos sem ver os contatos), a não ser que já
// esteja ligada, para dar para desligar; e uma chave ligada sem a dependência nunca (as metas sem R$ ficam inertes no
// servidor, decisão 14A).
const aparece = (item, permissions) => {
  const module = moduleByKey(item.area);
  const ligada = permissions.includes(item.chave);
  if (item.chave === 'conversation_message_delete')
    return emManage(module, permissions);
  if (ligada && !valeNoServidor(item.chave, permissions)) return false;
  return (
    ligada ||
    precisaDeManage(module, item.chave) ||
    getLevel(module, permissions) !== LEVELS.NONE
  );
};

// `preso`: vem com "Cuida de tudo nas vendas" (crm_admin), fica ligada e não desliga sozinha. `gravadas` é a função
// como será gravada. O alcance conta as gravadas mais as implicadas, como o servidor (GrantGuard#reach? com
// with_implied_permissions); o que aparece e o que está ligado contam também o que o crm_admin dá (chavesDoServidor),
// a mesma leitura da prévia. Ler o alcance pelo que o crm_admin dá punha no cadeado, sem motivo, o que o servidor
// aceitaria (revisão do #2308, rodada 4).
export const gruposDoCuidado = (giver, gravadas, lidas = gravadas) => {
  const alcance = comImplicadas(gravadas);
  const itens = CUIDADO.filter(item => aparece(item, lidas)).map(item => ({
    ...item,
    grupo: grupoDe(giver, item, alcance),
    preso: isExtraLocked(item.chave, lidas),
  }));
  const doGrupo = grupo => itens.filter(item => item.grupo === grupo);
  return {
    ligaJunto: doGrupo('ligaJunto'),
    ligaAgora: doGrupo('ligaAgora'),
    naoPode: doGrupo('naoPode').map(item => ({
      ...item,
      motivo: motivoDoCuidado(giver, item, alcance),
    })),
  };
};
