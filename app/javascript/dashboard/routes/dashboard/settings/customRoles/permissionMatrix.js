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

export const MODULE_GROUPS = [
  {
    key: 'SERVICE',
    modules: [
      {
        key: 'CONVERSATIONS',
        type: 'conversations',
        extras: [CONVERSATION_UNASSIGNED, CONVERSATION_PARTICIPATING],
      },
      {
        key: 'CONTACTS',
        levels: { view: 'contact_view', manage: 'contact_manage' },
      },
      {
        key: 'KNOWLEDGE_BASE',
        levels: {
          view: 'knowledge_base_view',
          manage: 'knowledge_base_manage',
        },
      },
      { key: 'REPORTS', levels: { view: 'report_manage' } },
      { key: 'CANNED_RESPONSES', levels: { manage: 'canned_response_manage' } },
    ],
  },
  {
    key: 'CRM',
    modules: [
      {
        key: 'CRM',
        type: 'crm',
        levels: { view: CRM_VIEW, manage: CRM_MANAGE_CARDS },
        extras: [
          CRM_MOVE_CARDS,
          'crm_view_reports',
          'crm_manage_pipelines',
          'crm_manage_ai',
          'crm_admin',
        ],
      },
    ],
  },
  {
    key: 'AUTONOMIA',
    modules: [
      {
        key: 'AUTONOMIA',
        levels: { view: 'autonomia_view', manage: 'autonomia_manage' },
      },
    ],
  },
  {
    key: 'MARKETING',
    modules: [
      {
        key: 'CAMPAIGNS',
        levels: { view: 'campaign_view', manage: 'campaign_manage' },
      },
    ],
  },
  {
    key: 'CONNECTIONS',
    modules: [
      {
        key: 'INBOXES',
        levels: { view: 'inbox_view', manage: 'inbox_manage' },
      },
    ],
  },
];

export const MODULES = MODULE_GROUPS.flatMap(group => group.modules);

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
  const rest = withoutKeys(permissions, keysOf(module));
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

export const toggleExtra = (module, key, permissions) => {
  if (!permissions.includes(key)) return [...permissions, key];
  const next = withoutKeys(permissions, [key]);
  // A limited conversation level needs at least one scope.
  const lostConversationScope =
    module.type === 'conversations' &&
    !next.some(
      k => k === CONVERSATION_UNASSIGNED || k === CONVERSATION_PARTICIPATING
    );
  return lostConversationScope ? permissions : next;
};

const build = levels =>
  Object.entries(levels).reduce((permissions, [moduleKey, level]) => {
    const module = MODULES.find(m => m.key === moduleKey);
    return setLevel(module, level, permissions);
  }, []);

export const PRESETS = {
  SUPERVISOR: () => [
    ...build({
      CONVERSATIONS: CONVERSATION_LEVELS.ALL,
      CONTACTS: LEVELS.MANAGE,
      KNOWLEDGE_BASE: LEVELS.VIEW,
      REPORTS: LEVELS.VIEW,
      CANNED_RESPONSES: LEVELS.MANAGE,
      CRM: LEVELS.MANAGE,
      AUTONOMIA: LEVELS.VIEW,
      CAMPAIGNS: LEVELS.VIEW,
      INBOXES: LEVELS.VIEW,
    }),
    'crm_view_reports',
  ],
  MARKETING: () => [
    ...build({
      CONTACTS: LEVELS.MANAGE,
      REPORTS: LEVELS.VIEW,
      CRM: LEVELS.VIEW,
      CAMPAIGNS: LEVELS.MANAGE,
    }),
    'crm_view_reports',
  ],
  AGENT: () =>
    build({
      CONVERSATIONS: CONVERSATION_LEVELS.LIMITED,
      CONTACTS: LEVELS.VIEW,
      KNOWLEDGE_BASE: LEVELS.VIEW,
      CANNED_RESPONSES: LEVELS.MANAGE,
      CRM: LEVELS.MANAGE,
    }),
};
