// Maps the flat custom-role permission keys to one access level per module (#452).
// Keys are never renamed, so roles saved before the matrix existed load unchanged.
// A `<module>_manage` key implies `<module>_view` on the backend, so only the highest key is stored.

export const LEVELS = { NONE: 'none', VIEW: 'view', MANAGE: 'manage' };
export const CONVERSATION_LEVELS = {
  NONE: 'none',
  LIMITED: 'limited',
  ALL: 'all',
};

const CONVERSATION_ALL = 'conversation_manage';
const CONVERSATION_UNASSIGNED = 'conversation_unassigned_manage';
const CONVERSATION_PARTICIPATING = 'conversation_participating_manage';
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
];

// Extras that touch personal data, money or other people's access. The editor asks
// for confirmation before turning them on.
export const SENSITIVE_EXTRAS = ['crm_manage_ai', 'crm_export', CRM_ADMIN];

export const MODULE_GROUPS = [
  {
    key: 'SERVICE',
    modules: [
      {
        key: 'CONVERSATIONS',
        type: 'conversations',
        icon: 'i-lucide-message-circle',
        extras: [CONVERSATION_UNASSIGNED, CONVERSATION_PARTICIPATING],
      },
      {
        key: 'CONTACTS',
        icon: 'i-lucide-contact',
        levels: { view: 'contact_view', manage: 'contact_manage' },
      },
      {
        key: 'KNOWLEDGE_BASE',
        icon: 'i-lucide-book-open',
        levels: {
          view: 'knowledge_base_view',
          manage: 'knowledge_base_manage',
        },
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
        extras: [
          CRM_MOVE_CARDS,
          'crm_view_reports',
          'crm_manage_pipelines',
          'crm_manage_ai',
          'crm_export',
          CRM_ADMIN,
        ],
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
    ],
  },
];

export const MODULES = MODULE_GROUPS.flatMap(group => group.modules);

export const moduleByKey = key => MODULES.find(module => module.key === key);

const keysOf = module => [
  ...Object.values(module.levels || {}),
  ...(module.extras || []),
];

const withoutKeys = (permissions, keys) =>
  permissions.filter(permission => !keys.includes(permission));

const unique = permissions => [...new Set(permissions)];

export const levelOptions = module => {
  if (module.type === 'conversations')
    return Object.values(CONVERSATION_LEVELS);
  return [
    LEVELS.NONE,
    ...[LEVELS.VIEW, LEVELS.MANAGE].filter(level => module.levels[level]),
  ];
};

// Three fixed positions so every row lines up: no access, view, edit.
// A module without a view level leaves the middle position empty.
const SLOT_BY_LEVEL = {
  [LEVELS.NONE]: 0,
  [LEVELS.VIEW]: 1,
  [CONVERSATION_LEVELS.LIMITED]: 1,
  [LEVELS.MANAGE]: 2,
  [CONVERSATION_LEVELS.ALL]: 2,
};

export const levelSlots = module => {
  const slots = [null, null, null];
  levelOptions(module).forEach(level => {
    slots[SLOT_BY_LEVEL[level]] = level;
  });
  return slots;
};

export const getLevel = (module, permissions) => {
  if (module.type === 'conversations') {
    if (permissions.includes(CONVERSATION_ALL)) return CONVERSATION_LEVELS.ALL;
    return CONVERSATION_KEYS.some(key => permissions.includes(key))
      ? CONVERSATION_LEVELS.LIMITED
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

const setConversationLevel = (level, permissions) => {
  const rest = withoutKeys(permissions, CONVERSATION_KEYS);
  if (level === CONVERSATION_LEVELS.ALL) return [...rest, ...CONVERSATION_KEYS];
  if (level === CONVERSATION_LEVELS.LIMITED) {
    const kept = permissions.filter(
      key =>
        key === CONVERSATION_UNASSIGNED || key === CONVERSATION_PARTICIPATING
    );
    return [...rest, ...(kept.length ? kept : [CONVERSATION_PARTICIPATING])];
  }
  return rest;
};

const setCrmLevel = (module, level, permissions) => {
  if (level === LEVELS.NONE) return withoutKeys(permissions, keysOf(module));
  const base = withoutKeys(permissions, [CRM_VIEW, CRM_MANAGE_CARDS]);
  // The CRM backend checks each key on its own, so crm_view is always stored.
  if (level === LEVELS.VIEW) return unique([...base, CRM_VIEW]);
  return unique([...base, CRM_VIEW, CRM_MANAGE_CARDS, CRM_MOVE_CARDS]);
};

export const setLevel = (module, level, permissions) => {
  if (module.type === 'conversations')
    return setConversationLevel(level, permissions);
  if (module.type === 'crm') return setCrmLevel(module, level, permissions);
  // Trocar entre ver e editar mantém as chaves a mais; sem acesso, sai tudo.
  const cleared =
    level === LEVELS.NONE ? keysOf(module) : Object.values(module.levels);
  const rest = withoutKeys(permissions, cleared);
  const key = module.levels[level];
  return key ? [...rest, key] : rest;
};

// Extras are the fine-grained toggles shown under a module once it has access.
export const visibleExtras = (module, permissions) => {
  const level = getLevel(module, permissions);
  if (!module.extras || level === LEVELS.NONE) return [];
  if (module.type === 'conversations')
    return level === CONVERSATION_LEVELS.LIMITED ? module.extras : [];
  // Editing cards already includes moving them.
  return level === LEVELS.MANAGE
    ? module.extras.filter(key => key !== CRM_MOVE_CARDS)
    : module.extras;
};

// The backend grants these through crm_admin, so they cannot be switched off on their own.
export const isExtraLocked = (key, permissions) =>
  permissions.includes(CRM_ADMIN) && CRM_EXTRAS_IMPLIED_BY_ADMIN.includes(key);

export const toggleExtra = (module, key, permissions) => {
  if (isExtraLocked(key, permissions)) return permissions;
  if (!permissions.includes(key)) {
    // Full CRM access switches every CRM option on, so the screen matches the backend.
    const implied = key === CRM_ADMIN ? CRM_EXTRAS_IMPLIED_BY_ADMIN : [];
    return unique([...permissions, key, ...implied]);
  }
  const next = withoutKeys(permissions, [key]);
  // A limited conversation level needs at least one scope.
  const lostConversationScope =
    module.type === 'conversations' &&
    !next.some(
      k => k === CONVERSATION_UNASSIGNED || k === CONVERSATION_PARTICIPATING
    );
  return lostConversationScope ? permissions : next;
};

// A pairing the backend needs for one action (e.g. prospecting → campaigns).
export const unmetSuggestion = (module, permissions) => {
  const { suggests } = module;
  if (!suggests || getLevel(module, permissions) !== suggests.level)
    return null;
  const target = moduleByKey(suggests.module);
  return getLevel(target, permissions) === LEVELS.MANAGE ? null : target;
};

export const sensitiveExtrasOn = permissions =>
  SENSITIVE_EXTRAS.filter(key => permissions.includes(key));

const build = levels =>
  Object.entries(levels).reduce(
    (permissions, [moduleKey, level]) =>
      setLevel(moduleByKey(moduleKey), level, permissions),
    []
  );

export const PRESETS = {
  AGENT: () =>
    build({
      CONVERSATIONS: CONVERSATION_LEVELS.LIMITED,
      CONTACTS: LEVELS.VIEW,
      KNOWLEDGE_BASE: LEVELS.VIEW,
      CRM: LEVELS.MANAGE,
    }),
  SUPERVISOR: () => [
    ...build({
      CONVERSATIONS: CONVERSATION_LEVELS.ALL,
      CONTACTS: LEVELS.MANAGE,
      KNOWLEDGE_BASE: LEVELS.VIEW,
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
  ],
  MARKETING: () => [
    ...build({
      CONTACTS: LEVELS.MANAGE,
      REPORTS: LEVELS.VIEW,
      CRM: LEVELS.VIEW,
      CAMPAIGNS: LEVELS.MANAGE,
      PROSPECTING: LEVELS.MANAGE,
      LABELS: LEVELS.MANAGE,
    }),
    'crm_view_reports',
  ],
  FINANCE: () => [
    ...build({ REPORTS: LEVELS.VIEW, CRM: LEVELS.VIEW }),
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
      KNOWLEDGE_BASE: LEVELS.VIEW,
      REPORTS: LEVELS.VIEW,
      CRM: LEVELS.VIEW,
      AUTONOMIA: LEVELS.VIEW,
      PROSPECTING: LEVELS.VIEW,
      CAMPAIGNS: LEVELS.VIEW,
      INBOXES: LEVELS.VIEW,
      AUTOMATIONS: LEVELS.VIEW,
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
        can: ['ALL_CONVERSATIONS', 'EDIT_CONTACTS', 'REPORTS', 'TEAM_SETUP'],
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
