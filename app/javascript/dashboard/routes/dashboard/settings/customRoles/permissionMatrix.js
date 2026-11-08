// Maps the flat custom-role permission keys to one access level per module (#452).
// Keys are never renamed, so roles saved before the matrix existed load unchanged.
// A `<module>_manage` key implies `<module>_view` on the backend, so only the highest key is stored.
import {
  CUSTOM_ROLE_MANAGE_PERMISSION,
  DESEMPENHO_VIEW_PERMISSION,
  FINANCIAL_MANAGE_PERMISSION,
  FINANCIAL_VIEW_PERMISSION,
  GRANT_ABOVE_OWN_PERMISSION,
  INTEGRATION_MANAGE_PERMISSION,
  KEY_DEPENDENCIES,
  META_ADS_MANAGE_PERMISSION,
  META_ADS_VIEW_PERMISSION,
  PEOPLE_MANAGE_PERMISSION,
  SALES_VALUE_VIEW_PERMISSION,
  TOKEN_MANAGE_PERMISSION,
} from 'dashboard/constants/permissions';

// Chaves do servidor que nenhuma tela de função mostra (#2352). knowledge_base_* guardam o portal de artigos para
// clientes do Chatwoot, que não está no menu do produto; a Central de Ajuda da plataforma é aberta a todos e não
// depende de chave. Funções que já têm essas chaves continuam com elas: o setLevel só mexe nas chaves da área que muda.
export const KEYS_OUTSIDE_MATRIX = [
  'knowledge_base_view',
  'knowledge_base_manage',
];

export const LEVELS = { NONE: 'none', VIEW: 'view', MANAGE: 'manage' };
// Conversas: só olha (conversation_view, #1800), ou atende as próprias (LIMITED) ou todas (ALL). Na tela, as duas
// últimas dividem a posição "Atender" e a escolha entre elas aparece embaixo.
export const CONVERSATION_LEVELS = {
  NONE: 'none',
  VIEW: 'view',
  LIMITED: 'limited',
  ALL: 'all',
};

const CONVERSATION_ALL = 'conversation_manage';
const CONVERSATION_UNASSIGNED = 'conversation_unassigned_manage';
const CONVERSATION_PARTICIPATING = 'conversation_participating_manage';
const CONVERSATION_VIEW = 'conversation_view';
// Apagar mensagem é chave própria (#1893): só para quem atende, nas próprias ou em todas.
const CONVERSATION_MESSAGE_DELETE = 'conversation_message_delete';
const CONVERSATION_KEYS = [
  CONVERSATION_ALL,
  CONVERSATION_UNASSIGNED,
  CONVERSATION_PARTICIPATING,
];

const CRM_VIEW = 'crm_view';
const CRM_MANAGE_CARDS = 'crm_manage_cards';
const CRM_MOVE_CARDS = 'crm_move_cards';
const CRM_ADMIN = 'crm_admin';
export const CRM_EXTRAS_IMPLIED_BY_ADMIN = [
  'crm_view_reports',
  'crm_manage_pipelines',
  'crm_manage_ai',
  'crm_export',
  'crm_delete_cards',
  'crm_metas_manage',
];

// Extras that touch personal data, money or other people's access. The editor asks
// for confirmation before turning them on.
export const SENSITIVE_EXTRAS = [
  'crm_manage_ai',
  'crm_export',
  // #1991: abre o R$ de cada pessoa da equipe e grava a meta de todos.
  'crm_metas_manage',
  // #2075: abre o R$ das vendas de toda a equipe.
  SALES_VALUE_VIEW_PERMISSION,
  CRM_ADMIN,
  'contact_export',
  'contact_delete',
  CONVERSATION_MESSAGE_DELETE,
  'campaign_send',
  CUSTOM_ROLE_MANAGE_PERMISSION,
  GRANT_ABOVE_OWN_PERMISSION,
];

export const MODULE_GROUPS = [
  {
    key: 'SERVICE',
    modules: [
      {
        key: 'CONVERSATIONS',
        type: 'conversations',
        icon: 'i-lucide-message-circle',
        extras: [
          CONVERSATION_UNASSIGNED,
          CONVERSATION_PARTICIPATING,
          CONVERSATION_VIEW,
          CONVERSATION_MESSAGE_DELETE,
        ],
      },
      {
        key: 'CONTACTS',
        icon: 'i-lucide-contact',
        levels: { view: 'contact_view', manage: 'contact_manage' },
        // Exportar e excluir são chaves próprias (#1845). Excluir só aparece para quem edita.
        extras: ['contact_export', 'contact_delete'],
        manageOnlyExtras: ['contact_delete'],
      },
      {
        key: 'REPORTS',
        icon: 'i-lucide-chart-spline',
        levels: { view: 'report_manage' },
      },
      {
        key: 'CANNED_RESPONSES',
        icon: 'i-lucide-message-square-quote',
        baseline: 'USE',
        levels: { manage: 'canned_response_manage' },
      },
    ],
  },
  {
    key: 'CRM',
    modules: [
      {
        key: 'CRM',
        type: 'crm',
        icon: 'i-lucide-kanban-square',
        levels: { view: CRM_VIEW, manage: CRM_MANAGE_CARDS },
        // Arquivar é chave própria (#1874), só para quem mexe nos cards; "Pode mexer" não a liga sozinho.
        extras: [
          CRM_MOVE_CARDS,
          'crm_delete_cards',
          // Valores de venda em R$ (#2075); as metas do mês (#1991) precisam dela.
          SALES_VALUE_VIEW_PERMISSION,
          // Metas do mês de cada pessoa (#1991): o R$ dos colegas é número comercial (Decisão 1 do #1871).
          'crm_metas_manage',
          'crm_view_reports',
          'crm_manage_pipelines',
          'crm_manage_ai',
          'crm_export',
          CRM_ADMIN,
        ],
        manageOnlyExtras: ['crm_delete_cards'],
      },
    ],
  },
  {
    key: 'AUTONOMIA',
    modules: [
      {
        key: 'AUTONOMIA',
        icon: 'i-lucide-bot',
        levels: { view: 'autonomia_view', manage: 'autonomia_manage' },
      },
      {
        // #2251 — painel de desempenho do agente e a exportação dele. Só ver; independente de Agentes.
        key: 'DESEMPENHO',
        icon: 'i-lucide-chart-line',
        levels: { view: DESEMPENHO_VIEW_PERMISSION },
      },
      {
        key: 'PROSPECTING',
        icon: 'i-lucide-search',
        levels: { view: 'prospecting_view', manage: 'prospecting_manage' },
        // Sem esta chave, quem não é administrador vê só as próprias buscas (#732).
        extras: ['prospecting_view_all_searches'],
        // Enviar leads para uma campanha exige campaign_manage no backend.
        suggests: { level: LEVELS.MANAGE, module: 'CAMPAIGNS' },
      },
      {
        key: 'INSURANCE',
        icon: 'i-lucide-calculator',
        levels: { view: 'insurance_view', manage: 'insurance_manage' },
      },
    ],
  },
  {
    key: 'MARKETING',
    modules: [
      {
        key: 'CAMPAIGNS',
        icon: 'i-lucide-megaphone',
        levels: { view: 'campaign_view', manage: 'campaign_manage' },
        // #1898: disparar é chave própria; sem ela, quem edita monta e deixa pronta.
        extras: ['campaign_send'],
        manageOnlyExtras: ['campaign_send'],
      },
      {
        // Modelos de mensagem do WhatsApp oficial (#1330, #1332). Editar cria, altera e
        // apaga na Meta; os modelos do sistema continuam só para ver.
        key: 'WHATSAPP_TEMPLATES',
        icon: 'i-lucide-message-square-text',
        levels: {
          view: 'whatsapp_templates_view',
          manage: 'whatsapp_templates_manage',
        },
      },
      {
        // Anúncios da Meta: ver o painel (#1794); editar conecta, configura e desconecta e age
        // sobre o consultor (#2070). meta_ads_manage só o administrador entrega, ou quem tem o
        // ajuste 'Pode entregar acima do próprio', que só o administrador liga (DELEGATION_KEYS).
        key: 'META_ADS',
        icon: 'i-lucide-chart-no-axes-combined',
        levels: {
          view: META_ADS_VIEW_PERMISSION,
          manage: META_ADS_MANAGE_PERMISSION,
        },
      },
      {
        // Seus posts (#2302): ver os posts e os números do Instagram e da Página das caixas; editar (F2 #2305)
        // responde, esconde, apaga e manda no privado. Os comentários só aparecem para quem vê a caixa.
        key: 'POSTS',
        icon: 'i-lucide-layout-grid',
        levels: { view: 'posts_view', manage: 'posts_manage' },
      },
    ],
  },
  {
    key: 'CONNECTIONS',
    modules: [
      {
        key: 'INBOXES',
        icon: 'i-lucide-inbox',
        settings: true,
        levels: { view: 'inbox_view', manage: 'inbox_manage' },
      },
      {
        // Integrações (#2027): conectar, configurar e desconectar integrações, webhooks, robôs e importações, e
        // reconectar um canal que já existe. Criar caixa nova fica com inbox_manage. Ver e trocar os tokens que a
        // plataforma gera é ajuste fino de quem cuida das integrações: as telas deles (robôs, webhooks, CRM/n8n)
        // ficam aqui. Só o administrador entrega as duas chaves, ou quem tem o ajuste 'Pode entregar
        // acima do próprio', que só o administrador liga (DELEGATION_KEYS).
        key: 'INTEGRATIONS',
        icon: 'i-lucide-plug',
        settings: true,
        levels: { manage: INTEGRATION_MANAGE_PERMISSION },
        extras: [TOKEN_MANAGE_PERMISSION],
        // Reconectar um canal acontece dentro das configurações da caixa.
        suggests: {
          level: LEVELS.MANAGE,
          module: 'INBOXES',
          targetLevel: LEVELS.VIEW,
        },
      },
    ],
  },
  {
    key: 'SETTINGS',
    modules: [
      {
        key: 'AUTOMATIONS',
        icon: 'i-lucide-repeat',
        settings: true,
        levels: { view: 'automation_view', manage: 'automation_manage' },
      },
      {
        key: 'SCHEDULING',
        icon: 'i-lucide-calendar-clock',
        settings: true,
        levels: { view: 'agendamento_view', manage: 'agendamento_manage' },
      },
      {
        key: 'LABELS',
        icon: 'i-lucide-tags',
        settings: true,
        baseline: 'APPLY',
        levels: { manage: 'label_manage' },
      },
      {
        key: 'ATTRIBUTES',
        icon: 'i-lucide-code',
        settings: true,
        baseline: 'FILL',
        levels: { manage: 'attribute_manage' },
      },
      {
        key: 'MACROS',
        icon: 'i-lucide-toy-brick',
        settings: true,
        baseline: 'PERSONAL',
        levels: { manage: 'macro_manage' },
      },
      {
        key: 'SLA',
        icon: 'i-lucide-timer',
        settings: true,
        levels: { manage: 'sla_manage' },
      },
      {
        // Regras de distribuição e capacidade das conversas (#1797).
        key: 'ASSIGNMENT',
        icon: 'i-lucide-user-cog',
        settings: true,
        levels: { manage: 'assignment_manage' },
        // Sem ver as caixas, a função só lista as caixas de que é membro nos formulários.
        suggests: {
          level: LEVELS.MANAGE,
          module: 'INBOXES',
          targetLevel: LEVELS.VIEW,
        },
      },
      {
        // Pessoas (#1931): agentes e times. Montar funções e entregar acima do próprio acesso
        // são ajustes finos de quem já cuida das pessoas; nenhum faz alguém virar administrador.
        key: 'PEOPLE',
        icon: 'i-lucide-users',
        settings: true,
        levels: { manage: PEOPLE_MANAGE_PERMISSION },
        extras: [CUSTOM_ROLE_MANAGE_PERMISSION, GRANT_ABOVE_OWN_PERMISSION],
      },
    ],
  },
  {
    key: 'FINANCE',
    modules: [
      {
        // Financeiro (#1969): ver os custos da conta em dinheiro (uso de IA) e a autorização de
        // cobranças da Meta; editar liga e desliga essa autorização. Plano e faturas ficam com o
        // administrador. As duas chaves só o administrador entrega, ou quem tem o ajuste 'Pode
        // entregar acima do próprio', que só o administrador liga (DELEGATION_KEYS).
        key: 'FINANCE',
        icon: 'i-lucide-wallet',
        levels: {
          view: FINANCIAL_VIEW_PERMISSION,
          manage: FINANCIAL_MANAGE_PERMISSION,
        },
      },
    ],
  },
];

export const MODULES = MODULE_GROUPS.flatMap(group => group.modules);

export const moduleByKey = key => MODULES.find(module => module.key === key);

// As chaves de uma área: as dos níveis e os ajustes.
export const keysOf = module => [
  ...Object.values(module.levels || {}),
  ...(module.extras || []),
];

const withoutKeys = (permissions, keys) =>
  permissions.filter(permission => !keys.includes(permission));

const unique = permissions => [...new Set(permissions)];

// `current`: o nível que a função já tem. Um nível que a área ainda não oferece (laterLevels) só aparece para ela.
export const levelOptions = (module, current = null) => {
  if (module.type === 'conversations')
    return Object.values(CONVERSATION_LEVELS);
  const later = module.laterLevels || [];
  return [
    LEVELS.NONE,
    ...[LEVELS.VIEW, LEVELS.MANAGE].filter(
      level =>
        module.levels[level] && (!later.includes(level) || level === current)
    ),
  ];
};

// Three fixed positions so every row lines up: no access, view, edit.
// A module without a view level leaves the middle position empty.
const SLOT_BY_LEVEL = {
  [LEVELS.NONE]: 0,
  [LEVELS.VIEW]: 1,
  [LEVELS.MANAGE]: 2,
};

const isConversationManaging = level =>
  level === CONVERSATION_LEVELS.LIMITED || level === CONVERSATION_LEVELS.ALL;

// The position a level lights up. Conversas: as próprias e todas acendem "Atender".
export const slotLevel = (module, level) =>
  module.type === 'conversations' && isConversationManaging(level)
    ? LEVELS.MANAGE
    : level;

export const levelSlots = (module, current = null) => {
  if (module.type === 'conversations')
    return [LEVELS.NONE, LEVELS.VIEW, LEVELS.MANAGE];
  const slots = [null, null, null];
  levelOptions(module, current).forEach(level => {
    slots[SLOT_BY_LEVEL[level]] = level;
  });
  return slots;
};

export const getLevel = (module, permissions) => {
  if (module.type === 'conversations') {
    if (permissions.includes(CONVERSATION_ALL)) return CONVERSATION_LEVELS.ALL;
    if (CONVERSATION_KEYS.some(key => permissions.includes(key)))
      return CONVERSATION_LEVELS.LIMITED;
    return permissions.includes(CONVERSATION_VIEW)
      ? CONVERSATION_LEVELS.VIEW
      : CONVERSATION_LEVELS.NONE;
  }
  const { view, manage } = module.levels;
  if (manage && permissions.includes(manage)) return LEVELS.MANAGE;
  if (view && permissions.includes(view)) return LEVELS.VIEW;
  // Legacy CRM roles may hold only extras (e.g. crm_admin) without crm_view.
  if (
    module.type === 'crm' &&
    keysOf(module).some(k => permissions.includes(k))
  )
    return LEVELS.VIEW;
  return LEVELS.NONE;
};

export const hasAccess = (module, permissions) =>
  getLevel(module, permissions) !== LEVELS.NONE;

// "Atender" sem dizer quais começa pelas próprias, a escolha mais estreita; quem já atende fica como está.
const setConversationLevel = (level, permissions) => {
  const rest = withoutKeys(permissions, [
    ...CONVERSATION_KEYS,
    CONVERSATION_VIEW,
  ]);
  if (level === CONVERSATION_LEVELS.ALL) return [...rest, ...CONVERSATION_KEYS];
  // Quem deixa de atender deixa de apagar mensagens.
  const notOperating = withoutKeys(rest, [CONVERSATION_MESSAGE_DELETE]);
  if (level === CONVERSATION_LEVELS.VIEW)
    return [...notOperating, CONVERSATION_VIEW];
  if (level === CONVERSATION_LEVELS.LIMITED || level === LEVELS.MANAGE) {
    if (
      isConversationManaging(getLevel({ type: 'conversations' }, permissions))
    ) {
      if (level === LEVELS.MANAGE) return permissions;
      // Sair de todas para as próprias sem alcance guardado começa pelas próprias.
      const limited = withoutKeys(permissions, [CONVERSATION_ALL]);
      const hasScope = limited.some(
        k => k === CONVERSATION_UNASSIGNED || k === CONVERSATION_PARTICIPATING
      );
      return hasScope ? limited : [...limited, CONVERSATION_PARTICIPATING];
    }
    // Quem só olhava passa a atender as próprias e continua lendo as outras.
    const keepsReading = permissions.includes(CONVERSATION_VIEW);
    return [
      ...rest,
      CONVERSATION_PARTICIPATING,
      ...(keepsReading ? [CONVERSATION_VIEW] : []),
    ];
  }
  return notOperating;
};

const setCrmLevel = (module, level, permissions) => {
  if (level === LEVELS.NONE) return withoutKeys(permissions, keysOf(module));
  const base = withoutKeys(permissions, [CRM_VIEW, CRM_MANAGE_CARDS]);
  // Any CRM level stores crm_view; the backend adds it too for every editing key (#2124). Voltar para ver tira o que é só de quem mexe.
  if (level === LEVELS.VIEW)
    return unique([
      ...withoutKeys(base, module.manageOnlyExtras || []),
      CRM_VIEW,
    ]);
  return unique([...base, CRM_VIEW, CRM_MANAGE_CARDS, CRM_MOVE_CARDS]);
};

export const setLevel = (module, level, permissions) => {
  if (module.type === 'conversations')
    return setConversationLevel(level, permissions);
  if (module.type === 'crm') return setCrmLevel(module, level, permissions);
  // Trocar entre ver e editar mantém as chaves a mais; sem acesso, sai tudo.
  // Voltar para ver tira as que só valem para quem edita.
  const manageOnly = level === LEVELS.VIEW ? module.manageOnlyExtras || [] : [];
  const cleared =
    level === LEVELS.NONE
      ? keysOf(module)
      : [...Object.values(module.levels), ...manageOnly];
  const rest = withoutKeys(permissions, cleared);
  const key = module.levels[level];
  return key ? [...rest, key] : rest;
};

// Extras are the fine-grained toggles shown under a module once it has access.
export const visibleExtras = (module, permissions) => {
  const level = getLevel(module, permissions);
  if (!module.extras) return [];
  // Sem acesso à área, só aparece o ajuste que ficou ligado (por exemplo, salvo pela API), para dar para desligar.
  if (level === LEVELS.NONE)
    return module.extras.filter(key => permissions.includes(key));
  if (module.type === 'conversations') {
    if (level === CONVERSATION_LEVELS.LIMITED) return module.extras;
    return level === CONVERSATION_LEVELS.ALL
      ? [CONVERSATION_MESSAGE_DELETE]
      : [];
  }
  // Editing cards already includes moving them.
  if (level === LEVELS.MANAGE)
    return module.extras.filter(key => key !== CRM_MOVE_CARDS);
  // Um ajuste só de quem edita fica visível enquanto estiver ligado, para dar para desligar.
  return module.extras.filter(
    key =>
      !(module.manageOnlyExtras || []).includes(key) ||
      permissions.includes(key)
  );
};

// The backend grants these through crm_admin, so they cannot be switched off on their own.
export const isExtraLocked = (key, permissions) =>
  permissions.includes(CRM_ADMIN) && CRM_EXTRAS_IMPLIED_BY_ADMIN.includes(key);

export const toggleExtra = (module, key, permissions) => {
  if (isExtraLocked(key, permissions)) return permissions;
  if (!permissions.includes(key)) {
    // Full CRM access switches every CRM option on, so the screen matches the backend.
    const implied = key === CRM_ADMIN ? CRM_EXTRAS_IMPLIED_BY_ADMIN : [];
    // #2075: a meta do mês é dinheiro. Ligar as metas liga os valores em R$; desligar os valores desliga as metas.
    const needed = KEY_DEPENDENCIES[key] ? [KEY_DEPENDENCIES[key]] : [];
    return unique([...permissions, key, ...implied, ...needed]);
  }
  // Um dependente que o crm_admin trava continua ligado.
  const dependents = Object.keys(KEY_DEPENDENCIES).filter(
    dependent =>
      KEY_DEPENDENCIES[dependent] === key &&
      !isExtraLocked(dependent, permissions)
  );
  const next = withoutKeys(permissions, [key, ...dependents]);
  // A limited conversation level needs at least one scope. Só os dois alcances contam: desligar outro ajuste
  // (ler as outras, apagar mensagens) nunca é barrado por isso.
  const isScopeKey =
    key === CONVERSATION_UNASSIGNED || key === CONVERSATION_PARTICIPATING;
  const lostConversationScope =
    module.type === 'conversations' &&
    isScopeKey &&
    !next.some(
      k => k === CONVERSATION_UNASSIGNED || k === CONVERSATION_PARTICIPATING
    );
  return lostConversationScope ? permissions : next;
};

// A pairing the backend needs for one action (e.g. prospecting → campaigns). The target needs
// `suggests.targetLevel` (edit by default) or more.
const LEVEL_RANK = { [LEVELS.NONE]: 0, [LEVELS.VIEW]: 1, [LEVELS.MANAGE]: 2 };
export const suggestedLevel = module =>
  module.suggests?.targetLevel || LEVELS.MANAGE;
export const unmetSuggestion = (module, permissions) => {
  const { suggests } = module;
  if (!suggests || getLevel(module, permissions) !== suggests.level)
    return null;
  const target = moduleByKey(suggests.module);
  const enough =
    LEVEL_RANK[getLevel(target, permissions)] >=
    LEVEL_RANK[suggestedLevel(module)];
  return enough ? null : target;
};

export const sensitiveExtrasOn = permissions =>
  SENSITIVE_EXTRAS.filter(key => permissions.includes(key));

// As áreas que guardam alguma destas chaves (#2115): diz à pessoa onde um modelo ficou incompleto.
export const modulesWithKeys = keys =>
  MODULES.filter(module =>
    [
      ...keysOf(module),
      ...(module.type === 'conversations' ? CONVERSATION_KEYS : []),
    ].some(key => keys.includes(key))
  );

const build = levels =>
  Object.entries(levels).reduce(
    (permissions, [moduleKey, level]) =>
      setLevel(moduleByKey(moduleKey), level, permissions),
    []
  );

// build() só guarda o nível de cada área; os ajustes finos que a frase do perfil promete entram à mão (#2115).
export const PRESETS = {
  AGENT: () => [
    ...build({
      CONVERSATIONS: CONVERSATION_LEVELS.LIMITED,
      CONTACTS: LEVELS.VIEW,
      CRM: LEVELS.MANAGE,
    }),
    // "Pegar da fila".
    CONVERSATION_UNASSIGNED,
  ],
  SUPERVISOR: () => [
    ...build({
      CONVERSATIONS: CONVERSATION_LEVELS.ALL,
      CONTACTS: LEVELS.MANAGE,
      REPORTS: LEVELS.VIEW,
      CANNED_RESPONSES: LEVELS.MANAGE,
      CRM: LEVELS.MANAGE,
      AUTONOMIA: LEVELS.VIEW,
      INBOXES: LEVELS.VIEW,
      AUTOMATIONS: LEVELS.VIEW,
      LABELS: LEVELS.MANAGE,
      MACROS: LEVELS.MANAGE,
    }),
    'crm_view_reports',
  ],
  SDR: () => [
    ...build({
      CONVERSATIONS: CONVERSATION_LEVELS.LIMITED,
      CONTACTS: LEVELS.MANAGE,
      CRM: LEVELS.MANAGE,
      PROSPECTING: LEVELS.MANAGE,
    }),
    CONVERSATION_UNASSIGNED,
  ],
  SALES_MANAGER: () => [
    ...build({
      CONVERSATIONS: CONVERSATION_LEVELS.ALL,
      CONTACTS: LEVELS.MANAGE,
      CRM: LEVELS.MANAGE,
      PROSPECTING: LEVELS.MANAGE,
      REPORTS: LEVELS.VIEW,
      CAMPAIGNS: LEVELS.VIEW,
      AUTONOMIA: LEVELS.VIEW,
    }),
    'crm_view_reports',
    'crm_manage_pipelines',
    'crm_export',
    'prospecting_view_all_searches',
    // Dono da meta (#2115): valores em R$ e as metas do mês da equipe. Chaves protegidas, saem para quem não as entrega.
    SALES_VALUE_VIEW_PERMISSION,
    'crm_metas_manage',
  ],
  MARKETING: () => [
    ...build({
      CONTACTS: LEVELS.MANAGE,
      REPORTS: LEVELS.VIEW,
      CRM: LEVELS.VIEW,
      CAMPAIGNS: LEVELS.MANAGE,
      PROSPECTING: LEVELS.MANAGE,
      LABELS: LEVELS.MANAGE,
      WHATSAPP_TEMPLATES: LEVELS.MANAGE,
    }),
    'crm_view_reports',
    'campaign_send',
    'contact_export',
  ],
  FINANCE: () => [
    ...build({ REPORTS: LEVELS.VIEW, CRM: LEVELS.VIEW, FINANCE: LEVELS.VIEW }),
    'crm_view_reports',
  ],
  OPERATIONS: () =>
    build({
      CONVERSATIONS: CONVERSATION_LEVELS.ALL,
      CONTACTS: LEVELS.MANAGE,
      CANNED_RESPONSES: LEVELS.MANAGE,
      AUTONOMIA: LEVELS.MANAGE,
      INBOXES: LEVELS.MANAGE,
      AUTOMATIONS: LEVELS.MANAGE,
      LABELS: LEVELS.MANAGE,
      ATTRIBUTES: LEVELS.MANAGE,
      MACROS: LEVELS.MANAGE,
      SLA: LEVELS.MANAGE,
    }),
  READ_ONLY: () => [
    ...build({
      CONTACTS: LEVELS.VIEW,
      REPORTS: LEVELS.VIEW,
      CRM: LEVELS.VIEW,
      AUTONOMIA: LEVELS.VIEW,
      PROSPECTING: LEVELS.VIEW,
      CAMPAIGNS: LEVELS.VIEW,
      INBOXES: LEVELS.VIEW,
      AUTOMATIONS: LEVELS.VIEW,
      WHATSAPP_TEMPLATES: LEVELS.VIEW,
      META_ADS: LEVELS.VIEW,
      SCHEDULING: LEVELS.VIEW,
      INSURANCE: LEVELS.VIEW,
    }),
    'crm_view_reports',
  ],
};

// Profiles on the first step, grouped by who the role is for.
// `can` and `cannot` are phrase keys under CUSTOM_ROLE.PROFILES.PHRASES.
export const PROFILE_GROUPS = [
  {
    key: 'SERVICE',
    profiles: [
      {
        key: 'AGENT',
        can: ['OWN_CONVERSATIONS', 'READ_CONTACTS_KB', 'MANAGE_DEALS'],
        cannot: ['OTHERS_CONVERSATIONS', 'REPORTS', 'SETTINGS'],
      },
      {
        key: 'SUPERVISOR',
        can: [
          'ALL_CONVERSATIONS',
          'EDIT_IMPORT_CONTACTS',
          'REPORTS',
          'TEAM_SETUP',
        ],
        cannot: ['DELETE_DATA', 'BILLING_INTEGRATIONS'],
      },
    ],
  },
  {
    key: 'SALES',
    profiles: [
      {
        key: 'SDR',
        can: ['PROSPECT', 'MANAGE_DEALS', 'OWN_CONVERSATIONS'],
        cannot: ['OTHERS_CONVERSATIONS', 'SEND_CAMPAIGNS', 'REPORTS'],
      },
      {
        key: 'SALES_MANAGER',
        can: [
          'ALL_CONVERSATIONS',
          'EDIT_PIPELINES',
          'EXPORT_CRM',
          'ALL_SEARCHES',
          'SET_GOALS',
        ],
        cannot: ['SEND_CAMPAIGNS', 'SETTINGS'],
      },
    ],
  },
  {
    key: 'MARKETING',
    profiles: [
      {
        key: 'MARKETING',
        can: ['SEND_CAMPAIGNS', 'EDIT_CONTACTS', 'PROSPECT', 'REPORTS'],
        cannot: ['ANSWER_CONVERSATIONS', 'EDIT_DEALS'],
      },
    ],
  },
  {
    key: 'MANAGEMENT',
    profiles: [
      {
        key: 'FINANCE',
        can: ['REPORTS', 'CRM_DASHBOARD'],
        cannot: ['ANSWER_CONVERSATIONS', 'CHANGE_ANYTHING'],
      },
      {
        key: 'OPERATIONS',
        can: [
          'ALL_CONVERSATIONS',
          'SETUP_INBOXES',
          'SETUP_RULES',
          'PUBLISH_AGENTS',
        ],
        cannot: ['REPORTS', 'BILLING_INTEGRATIONS'],
      },
      {
        key: 'READ_ONLY',
        can: ['SEE_EVERYTHING', 'REPORTS'],
        cannot: ['ANSWER_CONVERSATIONS', 'CHANGE_ANYTHING'],
      },
    ],
  },
];

export const BLANK_PROFILE = 'BLANK';

export const PROFILES = PROFILE_GROUPS.flatMap(group => group.profiles);

export const profilePermissions = key =>
  key === BLANK_PROFILE ? [] : PRESETS[key]();
