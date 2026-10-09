/* eslint-disable @intlify/vue-i18n/no-dynamic-keys */

// Chaves de tradução, não texto — quem exibe a frase (generateLogText, em
// Index.vue) resolve cada uma com t() antes de montar a frase. Guardar o
// texto em inglês aqui era a causa raiz da frase sair "metade em inglês"
// (#644): o template já era traduzido, mas esses valores entravam crus.
const roleMapping = {
  0: 'AUDIT_LOGS.ROLES.AGENT',
  1: 'AUDIT_LOGS.ROLES.ADMINISTRATOR',
};

const availabilityMapping = {
  0: 'AUDIT_LOGS.AVAILABILITY_STATUSES.ONLINE',
  1: 'AUDIT_LOGS.AVAILABILITY_STATUSES.OFFLINE',
  2: 'AUDIT_LOGS.AVAILABILITY_STATUSES.BUSY',
};

const fieldNameMapping = {
  role: 'AUDIT_LOGS.FIELDS.ROLE',
  availability: 'AUDIT_LOGS.FIELDS.AVAILABILITY',
};

const translationKeys = {
  'automationrule:create': `AUDIT_LOGS.AUTOMATION_RULE.ADD`,
  'automationrule:update': `AUDIT_LOGS.AUTOMATION_RULE.EDIT`,
  'automationrule:destroy': `AUDIT_LOGS.AUTOMATION_RULE.DELETE`,
  'webhook:create': `AUDIT_LOGS.WEBHOOK.ADD`,
  'webhook:update': `AUDIT_LOGS.WEBHOOK.EDIT`,
  'webhook:destroy': `AUDIT_LOGS.WEBHOOK.DELETE`,
  'inbox:create': `AUDIT_LOGS.INBOX.ADD`,
  'inbox:update': `AUDIT_LOGS.INBOX.EDIT`,
  'inbox:destroy': `AUDIT_LOGS.INBOX.DELETE`,
  'user:sign_in': `AUDIT_LOGS.USER_ACTION.SIGN_IN`,
  'user:sign_out': `AUDIT_LOGS.USER_ACTION.SIGN_OUT`,
  'team:create': `AUDIT_LOGS.TEAM.ADD`,
  'team:update': `AUDIT_LOGS.TEAM.EDIT`,
  'team:destroy': `AUDIT_LOGS.TEAM.DELETE`,
  'macro:create': `AUDIT_LOGS.MACRO.ADD`,
  'macro:update': `AUDIT_LOGS.MACRO.EDIT`,
  'macro:destroy': `AUDIT_LOGS.MACRO.DELETE`,
  'accountuser:create': `AUDIT_LOGS.ACCOUNT_USER.ADD`,
  'accountuser:update:self': `AUDIT_LOGS.ACCOUNT_USER.EDIT.SELF`,
  'accountuser:update:other': `AUDIT_LOGS.ACCOUNT_USER.EDIT.OTHER`,
  'accountuser:update:deleted': `AUDIT_LOGS.ACCOUNT_USER.EDIT.DELETED`,
  'inboxmember:create': `AUDIT_LOGS.INBOX_MEMBER.ADD`,
  'inboxmember:destroy': `AUDIT_LOGS.INBOX_MEMBER.REMOVE`,
  'teammember:create': `AUDIT_LOGS.TEAM_MEMBER.ADD`,
  'teammember:destroy': `AUDIT_LOGS.TEAM_MEMBER.REMOVE`,
  'account:update': `AUDIT_LOGS.ACCOUNT.EDIT`,
  'conversation:destroy': `AUDIT_LOGS.CONVERSATION.DELETE`,
  // Ação feita pelo Guia da Plataforma, depois da confirmação na tela (#536).
  'account:guide_action': `AUDIT_LOGS.GUIDE.ACTION`,
  'message:destroy': `AUDIT_LOGS.MESSAGE.DELETE`,
  'autonomia::agents::agent:update': `AUDIT_LOGS.AUTONOMIA_AGENT.EDIT`,
};

export const AUTONOMIA_OPERATION_KEYS = {
  voice_reply: 'AUDIT_LOGS.OPERATION_KEYS.VOICE_REPLY',
  voice_instructions: 'AUDIT_LOGS.OPERATION_KEYS.VOICE_INSTRUCTIONS',
  humanize_delivery: 'AUDIT_LOGS.OPERATION_KEYS.HUMANIZE_DELIVERY',
  operate_media: 'AUDIT_LOGS.OPERATION_KEYS.OPERATE_MEDIA',
  operate_reactions: 'AUDIT_LOGS.OPERATION_KEYS.OPERATE_REACTIONS',
  test_allowlist_phones: 'AUDIT_LOGS.OPERATION_KEYS.TEST_ALLOWLIST_PHONES',
  silence_tokens: 'AUDIT_LOGS.OPERATION_KEYS.SILENCE_TOKENS',
  native_tool_slugs: 'AUDIT_LOGS.OPERATION_KEYS.NATIVE_TOOL_SLUGS',
  debounce_seconds: 'AUDIT_LOGS.OPERATION_KEYS.DEBOUNCE_SECONDS',
  async_tools: 'AUDIT_LOGS.OPERATION_KEYS.ASYNC_TOOLS',
  async_poll_intervals: 'AUDIT_LOGS.OPERATION_KEYS.ASYNC_POLL_INTERVALS',
  async_deadline_seconds: 'AUDIT_LOGS.OPERATION_KEYS.ASYNC_DEADLINE_SECONDS',
};

const AUTONOMIA_BOOLEAN_OPERATION_KEYS = new Set([
  'voice_reply',
  'humanize_delivery',
  'operate_media',
  'operate_reactions',
  'async_tools',
]);

const AUTONOMIA_NUMBER_OPERATION_KEYS = new Set([
  'debounce_seconds',
  'async_deadline_seconds',
]);

const isRecord = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

const hiddenOperationValue = () => ({ type: 'hidden' });

const summarizeAutonomiaOperationValue = (operationKey, value) => {
  if (value === null || value === undefined) return { type: 'empty' };
  if (isRecord(value) && value.redacted === true) return hiddenOperationValue();

  if (AUTONOMIA_BOOLEAN_OPERATION_KEYS.has(operationKey)) {
    return typeof value === 'boolean'
      ? { type: 'boolean', value }
      : hiddenOperationValue();
  }

  if (AUTONOMIA_NUMBER_OPERATION_KEYS.has(operationKey)) {
    return typeof value === 'number' && Number.isFinite(value)
      ? { type: 'number', value }
      : hiddenOperationValue();
  }

  if (operationKey === 'test_allowlist_phones') {
    if (!Array.isArray(value) || value.some(item => typeof item !== 'string')) {
      return hiddenOperationValue();
    }
    if (!value.length) return { type: 'empty' };
    return {
      type: 'masked_list',
      count: value.length,
      preview: value.slice(0, 3),
    };
  }

  if (operationKey === 'voice_instructions') {
    return isRecord(value) &&
      Number.isInteger(value.length) &&
      value.length >= 0
      ? { type: 'length', value: value.length }
      : hiddenOperationValue();
  }

  if (operationKey === 'silence_tokens') {
    return isRecord(value) && Number.isInteger(value.count) && value.count >= 0
      ? { type: 'count', value: value.count }
      : hiddenOperationValue();
  }

  if (operationKey === 'native_tool_slugs') {
    return isRecord(value) && Number.isInteger(value.count) && value.count >= 0
      ? { type: 'count', value: value.count }
      : hiddenOperationValue();
  }

  if (operationKey === 'async_poll_intervals') {
    if (
      !isRecord(value) ||
      !Number.isInteger(value.count) ||
      value.count < 0 ||
      typeof value.min !== 'number' ||
      typeof value.max !== 'number' ||
      !Number.isFinite(value.min) ||
      !Number.isFinite(value.max)
    ) {
      return hiddenOperationValue();
    }
    return {
      type: 'range',
      count: value.count,
      min: value.min,
      max: value.max,
    };
  }

  return hiddenOperationValue();
};

const operationKeysFromAudit = auditLogItem => {
  const serializedKeys = Array.isArray(auditLogItem?.operation_keys)
    ? auditLogItem.operation_keys
    : [];
  if (serializedKeys.length) return serializedKeys;

  if (auditLogItem?.operation_key) return [auditLogItem.operation_key];

  const operationConfig = auditLogItem?.audited_changes?.operation_config;
  return isRecord(operationConfig) ? Object.keys(operationConfig) : [];
};

// O backend já mascara ou resume os valores antes de serializar o audit log.
// O front só aceita essa forma tipada e nunca transforma o objeto inteiro em texto.
export const getAutonomiaOperationChanges = auditLogItem => {
  if (
    auditLogItem?.auditable_type?.toLowerCase() !== 'autonomia::agents::agent'
  ) {
    return [];
  }

  const operationConfig = auditLogItem?.audited_changes?.operation_config;
  if (!isRecord(operationConfig)) return [];

  return operationKeysFromAudit(auditLogItem)
    .filter(operationKey =>
      Object.hasOwn(AUTONOMIA_OPERATION_KEYS, operationKey)
    )
    .map(operationKey => {
      const change = operationConfig[operationKey];
      if (
        !isRecord(change) ||
        !Object.hasOwn(change, 'old') ||
        !Object.hasOwn(change, 'new')
      ) {
        return null;
      }

      return {
        key: operationKey,
        label: AUTONOMIA_OPERATION_KEYS[operationKey],
        before: summarizeAutonomiaOperationValue(operationKey, change.old),
        after: summarizeAutonomiaOperationValue(operationKey, change.new),
      };
    })
    .filter(Boolean);
};

function extractAttrChange(attrChange) {
  if (Array.isArray(attrChange)) {
    return attrChange[attrChange.length - 1];
  }
  return attrChange;
}

export function extractChangedAccountUserValues(auditedChanges) {
  let changes = [];
  let values = [];

  // Check roles
  if (auditedChanges.role && auditedChanges.role.length) {
    changes.push(fieldNameMapping.role);
    values.push(roleMapping[extractAttrChange(auditedChanges.role)]);
  }

  // Check availability
  if (auditedChanges.availability && auditedChanges.availability.length) {
    changes.push(fieldNameMapping.availability);
    values.push(
      availabilityMapping[extractAttrChange(auditedChanges.availability)]
    );
  }

  return { changes, values };
}

function getAgentName(userId, agentList = []) {
  if (userId === null) {
    return 'System';
  }

  const agents = Array.isArray(agentList) ? agentList : [];
  const agentName = agents.find(agent => agent.id === userId)?.name;

  // If agent does not exist(removed/deleted), return userId
  return agentName || userId;
}

function handleAccountUserCreate(auditLogItem, translationPayload, agentList) {
  translationPayload.invitee = getAgentName(
    auditLogItem.audited_changes.user_id,
    agentList
  );

  const roleKey = auditLogItem.audited_changes.role;
  // 'AUDIT_LOGS.ROLES.UNKNOWN' como fallback se vier uma chave não reconhecida
  translationPayload.role = roleMapping[roleKey] || 'AUDIT_LOGS.ROLES.UNKNOWN';

  return translationPayload;
}

function handleAccountUserUpdate(auditLogItem, translationPayload, agentList) {
  if (auditLogItem.user_id !== auditLogItem.auditable?.user_id) {
    translationPayload.user = getAgentName(
      auditLogItem.auditable?.user_id,
      agentList
    );
  }

  const accountUserChanges = extractChangedAccountUserValues(
    auditLogItem.audited_changes
  );
  if (accountUserChanges) {
    translationPayload.attributes = accountUserChanges.changes;
    translationPayload.values = accountUserChanges.values;
  }
  return translationPayload;
}

function setUserInPayload(auditLogItem, translationPayload, agentList) {
  const userIdChange = auditLogItem.audited_changes.user_id;
  if (userIdChange && userIdChange !== undefined) {
    translationPayload.user = getAgentName(userIdChange, agentList);
  }
  return translationPayload;
}

function setTeamIdInPayload(auditLogItem, translationPayload) {
  if (auditLogItem.audited_changes.team_id) {
    translationPayload.team_id = auditLogItem.audited_changes.team_id;
  }
  return translationPayload;
}

function setInboxIdInPayload(auditLogItem, translationPayload) {
  if (auditLogItem.audited_changes.inbox_id) {
    translationPayload.inbox_id = auditLogItem.audited_changes.inbox_id;
  }
  return translationPayload;
}

function handleInboxTeamMember(auditLogItem, translationPayload, agentList) {
  if (auditLogItem.audited_changes) {
    translationPayload = setUserInPayload(
      auditLogItem,
      translationPayload,
      agentList
    );
    translationPayload = setTeamIdInPayload(auditLogItem, translationPayload);
    translationPayload = setInboxIdInPayload(auditLogItem, translationPayload);
  }
  return translationPayload;
}

function handleAccountUser(
  auditLogItem,
  translationPayload,
  agentList,
  action
) {
  if (action === 'create') {
    return handleAccountUserCreate(auditLogItem, translationPayload, agentList);
  }

  if (action === 'update') {
    return handleAccountUserUpdate(auditLogItem, translationPayload, agentList);
  }

  return translationPayload;
}

export function generateTranslationPayload(auditLogItem, agentList) {
  let translationPayload = {
    agentName: getAgentName(auditLogItem.user_id, agentList),
    id: auditLogItem.auditable_id,
  };

  const auditableType = auditLogItem.auditable_type.toLowerCase();
  const action = auditLogItem.action.toLowerCase();

  if (auditableType === 'conversation' && action === 'destroy') {
    translationPayload.id =
      auditLogItem.audited_changes?.display_id || auditLogItem.auditable_id;
  }

  if (auditableType === 'message' && action === 'destroy') {
    translationPayload.conversationId =
      auditLogItem.audited_changes?.display_id;
  }

  // A frase que a pessoa leu e confirmou no cartão do Guia — é ela que diz o
  // que mudou, em português, sem rota nem jargão.
  if (auditableType === 'account' && action === 'guide_action') {
    translationPayload.frase = auditLogItem.audited_changes?.frase || '';
  }

  if (auditableType === 'accountuser') {
    translationPayload = handleAccountUser(
      auditLogItem,
      translationPayload,
      agentList,
      action
    );
  }

  if (auditableType === 'inboxmember' || auditableType === 'teammember') {
    translationPayload = handleInboxTeamMember(
      auditLogItem,
      translationPayload,
      agentList
    );
  }

  if (auditableType === 'autonomia::agents::agent') {
    translationPayload.actor =
      auditLogItem.actor?.name ||
      auditLogItem.username ||
      translationPayload.agentName;
    const operationKeys = operationKeysFromAudit(auditLogItem);
    if (operationKeys.length === 1) {
      translationPayload.operationKey =
        AUTONOMIA_OPERATION_KEYS[operationKeys[0]] ||
        'AUDIT_LOGS.OPERATION_KEYS.UNKNOWN';
    } else if (operationKeys.length > 1) {
      translationPayload.operationKey = 'AUDIT_LOGS.OPERATION_KEYS.MULTIPLE';
    }
  }

  return translationPayload;
}

function getAccountUserUpdateSuffix(auditLogItem) {
  if (auditLogItem.auditable === null) {
    // If the user is deleted, we don't need to check if the user is the same as the auditLogItem.user_id
    // Else we can use the deleted translation key
    // It doesn't need the agent name
    return ':deleted';
  }
  return auditLogItem.user_id === auditLogItem.auditable.user_id
    ? ':self'
    : ':other';
}

// payload.role/attributes/values chegam como chaves de i18n (ver
// roleMapping/availabilityMapping/fieldNameMapping acima), não como texto —
// resolve cada uma com t() antes de montar a frase. Guardar o texto em
// inglês nesses campos era a causa raiz da frase sair "metade em inglês"
// (#644): o template já era traduzido, mas os valores entravam crus.
export const translateLogPayload = (payload, t) => {
  const translateKey = key => (key ? t(key) : key);
  const translateAndJoin = value => {
    if (!Array.isArray(value)) return translateKey(value);
    return value.map(item => translateKey(item)).join(', ');
  };

  const translatedPayload = {
    ...payload,
    role: translateKey(payload.role),
    attributes: translateAndJoin(payload.attributes),
    values: translateAndJoin(payload.values),
  };

  if (Object.prototype.hasOwnProperty.call(payload, 'operationKey')) {
    translatedPayload.operationKey = translateKey(payload.operationKey);
  }

  return translatedPayload;
};

export const generateLogActionKey = auditLogItem => {
  const auditableType = auditLogItem.auditable_type.toLowerCase();
  const action = auditLogItem.action.toLowerCase();
  let logActionKey = `${auditableType}:${action}`;

  if (auditableType === 'accountuser' && action === 'update') {
    logActionKey += getAccountUserUpdateSuffix(auditLogItem);
  }

  return translationKeys[logActionKey] || '';
};

export const EVENT_TYPE_GROUPS = [
  { key: 'ACCESS', types: [{ value: 'User', key: 'SIGN_IN_OUT' }] },
  {
    key: 'AGENTS_TEAMS',
    types: [
      { value: 'AccountUser', key: 'AGENTS' },
      { value: 'Autonomia::Agents::Agent', key: 'AUTONOMIA_AGENTS' },
      { value: 'Team', key: 'TEAMS' },
      { value: 'TeamMember', key: 'TEAM_MEMBERS' },
      { value: 'InboxMember', key: 'INBOX_MEMBERS' },
    ],
  },
  {
    key: 'CONFIGURATION',
    types: [
      { value: 'Account', key: 'ACCOUNT' },
      { value: 'Inbox', key: 'INBOXES' },
      { value: 'Webhook', key: 'WEBHOOKS' },
      { value: 'AutomationRule', key: 'AUTOMATION_RULES' },
      { value: 'Macro', key: 'MACROS' },
    ],
  },
  {
    key: 'CONVERSATIONS',
    types: [
      { value: 'Conversation', key: 'CONVERSATION_DELETIONS' },
      { value: 'Message', key: 'MESSAGE_DELETIONS' },
    ],
  },
];

const SUPPORTED_TYPES = EVENT_TYPE_GROUPS.flatMap(({ types }) =>
  types.map(({ value }) => value)
);
const SORT_ORDERS = ['asc', 'desc'];

export const auditLogFiltersFromQuery = (query = {}) => {
  const filters = { page: Number(query.page) || 1 };

  if (query.q) filters.q = query.q;
  if (SUPPORTED_TYPES.includes(query.type)) filters.types = [query.type];
  if (SORT_ORDERS.includes(query.sort)) filters.sort = query.sort;

  const agentId = Number(query.agent_id);
  if (Number.isInteger(agentId) && agentId > 0) filters.agent_id = agentId;
  if (
    Object.prototype.hasOwnProperty.call(
      AUTONOMIA_OPERATION_KEYS,
      query.operation_key
    )
  ) {
    filters.operation_key = query.operation_key;
  }

  const since = Number(query.since);
  const until = Number(query.until);
  if (since > 0 && until > 0) {
    filters.since = since;
    filters.until = until;
  }

  return filters;
};

export const buildAuditLogRouteQuery = (query = {}) =>
  Object.fromEntries(
    Object.entries(query).filter(
      ([, value]) => value !== undefined && value !== ''
    )
  );
