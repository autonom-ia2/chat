import { CONVERSATION_PRIORITY_ORDER } from 'shared/constants/messages';
import { isAssignedToUser } from 'dashboard/helper/assigneeHelper';

export const findPendingMessageIndex = (chat, message) => {
  const { echo_id: tempMessageId } = message;
  return chat.messages.findIndex(
    m => m.id === message.id || m.id === tempMessageId
  );
};

export const filterByStatus = (chatStatus, filterStatus) =>
  filterStatus === 'all' ? true : chatStatus === filterStatus;

export const filterByInbox = (shouldFilter, inboxId, chatInboxId) => {
  const isOnInbox = Number(inboxId) === chatInboxId;
  return inboxId ? isOnInbox && shouldFilter : shouldFilter;
};

export const filterByTeam = (shouldFilter, teamId, chatTeamId) => {
  const isOnTeam = Number(teamId) === chatTeamId;
  return teamId ? isOnTeam && shouldFilter : shouldFilter;
};

export const filterByLabel = (shouldFilter, labels, chatLabels) => {
  const isOnLabel = labels.every(label => chatLabels.includes(label));
  return labels.length ? isOnLabel && shouldFilter : shouldFilter;
};
// Filtro "Funil" (multifunil #1150): crm_pipeline_ids vem na conversa lida da API, só com os funis que a pessoa
// enxerga; crm_pipeline_hidden diz que há card em funil oculto para ela. "Sem assunto" = nenhum dos dois.
// Conversa sem o campo (vinda do websocket, ainda não lida da API) não entra numa lista filtrada por funil.
export const filterByCrmPipeline = (
  shouldFilter,
  crmPipelineId,
  chatPipelineIds,
  hasHiddenPipeline = false
) => {
  if (!crmPipelineId) return shouldFilter;
  if (!Array.isArray(chatPipelineIds)) return false;
  if (crmPipelineId === 'none')
    return shouldFilter && chatPipelineIds.length === 0 && !hasHiddenPipeline;
  return (
    shouldFilter && chatPipelineIds.map(String).includes(String(crmPipelineId))
  );
};

export const filterByUnattended = (
  shouldFilter,
  conversationType,
  firstReplyOn,
  waitingSince
) => {
  return conversationType === 'unattended'
    ? (!firstReplyOn || !!waitingSince) && shouldFilter
    : shouldFilter;
};

// Filtros pelo link (#1883): quem decide o que entra é o servidor. Com o filtro ligado, a lista mostra só as conversas
// que ele mandou (os ids guardados na store); a que chega ou muda pelo websocket espera a próxima releitura. A conversa
// aberta fica na lista enquanto estiver aberta, mesmo que tenha deixado de casar com o filtro; ao trocar de conversa,
// ela sai.
export const filterPeloFiltroDoLink = (
  conversations,
  ligado,
  ids,
  idDaAberta
) => {
  if (!ligado) return conversations;
  const doServidor = new Set(ids);
  return conversations.filter(
    ({ id }) => doServidor.has(id) || (Boolean(idDaAberta) && id === idDaAberta)
  );
};

export const applyPageFilters = (conversation, filters) => {
  const {
    inboxId,
    status,
    labels = [],
    teamId,
    conversationType,
    crmPipelineId,
  } = filters;
  const {
    status: chatStatus,
    inbox_id: chatInboxId,
    labels: chatLabels = [],
    meta = {},
    first_reply_created_at: firstReplyOn,
    waiting_since: waitingSince,
    crm_pipeline_ids: chatPipelineIds,
    crm_pipeline_hidden: hasHiddenPipeline,
  } = conversation;
  const team = meta.team || {};
  const { id: chatTeamId } = team;

  let shouldFilter = filterByStatus(chatStatus, status);
  shouldFilter = filterByInbox(shouldFilter, inboxId, chatInboxId);
  shouldFilter = filterByTeam(shouldFilter, teamId, chatTeamId);
  shouldFilter = filterByLabel(shouldFilter, labels, chatLabels);
  shouldFilter = filterByUnattended(
    shouldFilter,
    conversationType,
    firstReplyOn,
    waitingSince
  );
  shouldFilter = filterByCrmPipeline(
    shouldFilter,
    crmPipelineId,
    chatPipelineIds,
    hasHiddenPipeline
  );

  return shouldFilter;
};

// Espera pessoa: sem responsável humano e sem robô, ou o robô passou e espera (o mesmo awaiting_person? do servidor).
const isAwaitingPerson = conversation => {
  const { assignee, assignee_type: assigneeType } = conversation.meta;
  if (assignee && assigneeType !== 'AgentBot') return false;
  return (
    !assignee ||
    Boolean(conversation.additional_attributes?.bot_handoff_waiting_since)
  );
};

/**
 * Whether the user can operate the conversation (reply, assign, change status), the same rule as
 * ConversationPolicy#show? on the server. Reading is wider: see applyRoleFilter (#1800).
 *
 * @param {Object} conversation - The conversation object to check permissions for
 * @param {string} role - The user's role (administrator, agent, etc.)
 * @param {Array<string>} permissions - List of permission strings the user has
 * @param {number|string} currentUserId - The ID of the current user
 * @param {boolean} isParticipant - Whether the user participates in the conversation
 * @returns {boolean} - Whether the user can operate this conversation
 */
export const canOperateConversation = (
  conversation,
  role,
  permissions,
  currentUserId,
  isParticipant = false
) => {
  // the role === "agent" check is typically not correct on it's own
  // the backend handles this by checking the custom_role_id at the user model
  // here however, the `getUserRole` returns "custom_role" if the id is present,
  // so we can check the role === "agent" directly
  if (['administrator', 'agent'].includes(role)) {
    return true;
  }

  // Check for full conversation management permission
  if (permissions.includes('conversation_manage')) {
    return true;
  }

  // Só a pessoa responsável: AgentBot e Captain::Assistant com o mesmo id não contam (#2249).
  const souOResponsavel = isAssignedToUser(conversation, currentUserId);

  // Check unassigned management permission
  if (permissions.includes('conversation_unassigned_manage')) {
    return isAwaitingPerson(conversation) || souOResponsavel;
  }

  // Check participating conversation management permission
  if (permissions.includes('conversation_participating_manage')) {
    return souOResponsavel || isParticipant;
  }

  return false;
};

const CONVERSATION_OPERATE_KEYS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

// Só lê conversas: tem conversation_view e nenhuma chave de operar. Não começa conversa (create? no servidor, #1800).
export const readsOnlyConversations = permissions =>
  permissions.includes('conversation_view') &&
  !CONVERSATION_OPERATE_KEYS.some(key => permissions.includes(key));

// Ver na lista: quem opera, e quem só lê (conversation_view lê toda conversa da caixa, #1800).
export const applyRoleFilter = (
  conversation,
  role,
  permissions,
  currentUserId
) =>
  permissions.includes('conversation_view') ||
  canOperateConversation(conversation, role, permissions, currentUserId);

const SORT_OPTIONS = {
  last_activity_at_asc: ['sortOnLastActivityAt', 'asc'],
  last_activity_at_desc: ['sortOnLastActivityAt', 'desc'],
  created_at_asc: ['sortOnCreatedAt', 'asc'],
  created_at_desc: ['sortOnCreatedAt', 'desc'],
  priority_asc: ['sortOnPriority', 'asc'],
  priority_desc: ['sortOnPriority', 'desc'],
  waiting_since_asc: ['sortOnWaitingSince', 'asc'],
  waiting_since_desc: ['sortOnWaitingSince', 'desc'],
  priority_desc_created_at_asc: ['sortOnPriorityCreatedAt', 'desc'],
  unread: ['sortOnUnread', 'desc'],
};
const sortAscending = (valueA, valueB) => valueA - valueB;
const sortDescending = (valueA, valueB) => valueB - valueA;

const getSortOrderFunction = sortOrder =>
  sortOrder === 'asc' ? sortAscending : sortDescending;

const sortConfig = {
  sortOnLastActivityAt: (a, b, sortDirection) =>
    getSortOrderFunction(sortDirection)(a.last_activity_at, b.last_activity_at),

  sortOnCreatedAt: (a, b, sortDirection) =>
    getSortOrderFunction(sortDirection)(a.created_at, b.created_at) ||
    getSortOrderFunction(sortDirection)(a.id, b.id),

  sortOnPriority: (a, b, sortDirection) => {
    const DEFAULT_FOR_NULL = sortDirection === 'asc' ? 5 : 0;

    const p1 = CONVERSATION_PRIORITY_ORDER[a.priority] || DEFAULT_FOR_NULL;
    const p2 = CONVERSATION_PRIORITY_ORDER[b.priority] || DEFAULT_FOR_NULL;
    const priorityDiff = getSortOrderFunction(sortDirection)(p1, p2);
    if (priorityDiff !== 0) return priorityDiff;

    return sortDescending(a.last_activity_at, b.last_activity_at);
  },

  sortOnPriorityCreatedAt: (a, b) => {
    const DEFAULT_FOR_NULL = 0;
    const p1 = CONVERSATION_PRIORITY_ORDER[a.priority] || DEFAULT_FOR_NULL;
    const p2 = CONVERSATION_PRIORITY_ORDER[b.priority] || DEFAULT_FOR_NULL;
    if (p1 !== p2) return p2 - p1;
    return a.created_at - b.created_at;
  },

  sortOnWaitingSince: (a, b, sortDirection) => {
    const sortFunc = getSortOrderFunction(sortDirection);
    if (!a.waiting_since || !b.waiting_since) {
      if (!a.waiting_since && !b.waiting_since) {
        return sortAscending(a.created_at, b.created_at);
      }
      return a.waiting_since ? -1 : 1;
    }

    return sortFunc(a.waiting_since, b.waiting_since);
  },

  sortOnUnread: (a, b) => {
    const unreadCountDiff = (b.unread_count || 0) - (a.unread_count || 0);
    if (unreadCountDiff !== 0) return unreadCountDiff;

    return (b.last_activity_at || 0) - (a.last_activity_at || 0);
  },
};

export const sortComparator = (a, b, sortKey) => {
  const [sortMethod, sortDirection] =
    SORT_OPTIONS[sortKey] || SORT_OPTIONS.last_activity_at_desc;
  return sortConfig[sortMethod](a, b, sortDirection);
};
