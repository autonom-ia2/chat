import AutonomiaSourcesAPI from '../../api/autonomia/sources';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Knowledge sources are a per-agent sub-resource (no global records-by-id list),
// so this module is hand-rolled rather than using the CRUD factory. State holds
// the source list for the currently viewed agent; switching agents refetches.
//
// Ingestion is asynchronous (IngestJob): a freshly created/re-synced source is
// `pending`/`processing` and only flips to `ready`/`failed` later. We poll
// `fetch` while any source is still ingesting so the UI reflects progress.
const POLL_INTERVAL = 4000;
const INGESTING_STATUSES = ['pending', 'processing'];

const sourcesRequest = useAbortableRequest();
let pollTimer = null;

const currentEpoch = $state => $state?.epoch ?? 0;
const isCurrentProjection = ($state, agentId, epoch) =>
  $state?.activeAgentId === agentId && currentEpoch($state) === epoch;

const clearPoll = () => {
  if (pollTimer) {
    clearTimeout(pollTimer);
    pollTimer = null;
  }
};

const beginProjection = (commit, $state, agentId) => {
  sourcesRequest.abort();
  clearPoll();
  commit('BEGIN_PROJECTION', agentId);
  return currentEpoch($state);
};

const ensureAgentProjection = (commit, $state, agentId) => {
  if ($state.activeAgentId === agentId) return currentEpoch($state);
  const epoch = beginProjection(commit, $state, agentId);
  return epoch;
};

// A source is still "settling" while it ingests (pending/processing) OR while it
// has finished ingesting (`ready`) but the quality review has not landed yet
// (`review.status == null`). The Revisor runs after ingestion, so a `ready`
// source with no review is still in flight as far as the Materiais UI cares.
const isIngesting = source =>
  INGESTING_STATUSES.includes(source?.status) ||
  (source?.status === 'ready' && source?.review?.status == null);

export const state = {
  epoch: 0,
  activeAgentId: null,
  records: [],
  uiFlags: {
    fetchingList: false,
    creatingItem: false,
    deletingItem: false,
    resyncingItem: false,
  },
};

export const getters = {
  getSources($state) {
    return $state.records;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  // "O que ela sabe" — documents/links that become RAG knowledge. Defaults to
  // `knowledge` so payloads without the `kind` column (backend gap #2) all land
  // in the first tab.
  getKnowledgeSources($state) {
    return $state.records.filter(
      record => (record.kind ?? 'knowledge') === 'knowledge'
    );
  },
  // "O que ela pode enviar" — media the agent forwards to customers. Empty until
  // the backend serializes `kind: 'media'`.
  getMediaSources($state) {
    return $state.records.filter(record => record.kind === 'media');
  },
  // Whether the payload carries the saber/enviar `kind` split at all; gates the
  // second tab so we render a single tab until the backend ships gap #2.
  hasMediaKind($state) {
    return $state.records.some(record => record.kind != null);
  },
  // Any source the Revisor flagged for re-upload blocks "Continuar".
  getNeedsResend($state) {
    return $state.records.some(
      record => record.review?.status === 'needs_resend'
    );
  },
  // A source whose ingestion failed (`status: 'failed'`) never gets a review
  // verdict, so it would silently keep "Continuar" disabled forever via
  // getAllReviewed. Surface it like a resend so the UI can explain why the user
  // is stuck (the card offers Reenviar). Keeps the gate honest.
  getHasFailed($state) {
    return $state.records.some(record => record.status === 'failed');
  },
  // Anything that needs the user's attention before the step can close: a
  // Revisor resend request OR a hard ingestion failure. Drives the "why is
  // Continuar disabled" banner.
  getNeedsAttention($state, $getters) {
    return $getters.getNeedsResend || $getters.getHasFailed;
  },
  // Every source has settled into an acceptable verdict (accepted, or low-
  // confidence-but-usable needs_review). Empty list = nothing to gate on.
  getAllReviewed($state) {
    return (
      $state.records.length > 0 &&
      $state.records.every(record =>
        ['accepted', 'needs_review'].includes(record.review?.status)
      )
    );
  },
  // KB-first: a etapa base fecha pela CONHECIMENTO só (mídia de envio não passa pelo Revisor, logo
  // nunca ficaria "revisada" e travaria o gate). Espelha getAllReviewed restrito à knowledge.
  getKnowledgeReviewed($state, $getters) {
    const knowledge = $getters.getKnowledgeSources;
    return (
      knowledge.length > 0 &&
      knowledge.every(record =>
        ['accepted', 'needs_review'].includes(record.review?.status)
      )
    );
  },
  // Pendência (resend/falha) restrita à knowledge — mesmo motivo do escopo acima.
  getKnowledgeNeedsAttention($state, $getters) {
    return $getters.getKnowledgeSources.some(
      record =>
        record.review?.status === 'needs_resend' || record.status === 'failed'
    );
  },
};

const upsertItem = (items, item) => {
  const index = items.findIndex(existing => existing.id === item.id);
  if (index === -1) return [item, ...items];
  return items.map(existing => (existing.id === item.id ? item : existing));
};

export const actions = {
  fetch: async (
    { commit, dispatch, state: $state },
    { agentId, expectedEpoch } = {}
  ) => {
    if (!agentId) return null;
    if (
      expectedEpoch != null &&
      !isCurrentProjection($state, agentId, expectedEpoch)
    )
      return null;
    const epoch = beginProjection(commit, $state, agentId);
    // Zera a lista antes de buscar: ao trocar de agente o painel remonta, mas o
    // store é module-wide — sem isto os itens do agente anterior ficam visíveis
    // (o guard de loading é `fetchingList && !sources.length`) até o fetch voltar.
    commit('SET', []);
    commit('SET_UI_FLAG', {
      fetchingList: true,
      creatingItem: false,
      deletingItem: false,
      resyncingItem: false,
    });
    try {
      const response = await sourcesRequest.run(signal =>
        AutonomiaSourcesAPI.get(agentId, { signal })
      );
      if (!response || !isCurrentProjection($state, agentId, epoch))
        return null;
      const { data } = response;
      const records = data.payload || data || [];
      commit('SET', records);
      dispatch('schedulePoll', { agentId, records, epoch });
      return records;
    } catch (error) {
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      return throwErrorMessage(error);
    } finally {
      if (isCurrentProjection($state, agentId, epoch))
        commit('SET_UI_FLAG', { fetchingList: false });
    }
  },

  // `descriptor` is { url } for a link or { file } for an upload; the API
  // client maps it to the backend `source[...]` contract.
  create: async (
    { commit, dispatch, state: $state },
    { agentId, descriptor }
  ) => {
    const epoch = ensureAgentProjection(commit, $state, agentId);
    commit('SET_UI_FLAG', { creatingItem: true });
    try {
      const { data } = await AutonomiaSourcesAPI.create(agentId, descriptor);
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      const source = data.payload || data;
      commit('UPSERT', source);
      dispatch('schedulePoll', { agentId, records: [source], epoch });
      return source;
    } catch (error) {
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      return throwErrorMessage(error);
    } finally {
      if (isCurrentProjection($state, agentId, epoch))
        commit('SET_UI_FLAG', { creatingItem: false });
    }
  },

  remove: async ({ commit, state: $state }, { agentId, sourceId }) => {
    const epoch = ensureAgentProjection(commit, $state, agentId);
    commit('SET_UI_FLAG', { deletingItem: true });
    try {
      await AutonomiaSourcesAPI.delete(agentId, sourceId);
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      commit('DELETE', sourceId);
      return sourceId;
    } catch (error) {
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      return throwErrorMessage(error);
    } finally {
      if (isCurrentProjection($state, agentId, epoch))
        commit('SET_UI_FLAG', { deletingItem: false });
    }
  },

  resync: async (
    { commit, dispatch, state: $state },
    { agentId, sourceId }
  ) => {
    const epoch = ensureAgentProjection(commit, $state, agentId);
    commit('SET_UI_FLAG', { resyncingItem: true });
    try {
      const { data } = await AutonomiaSourcesAPI.resync(agentId, sourceId);
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      const source = data.payload || data;
      commit('UPSERT', source);
      dispatch('schedulePoll', { agentId, records: [source], epoch });
      return source;
    } catch (error) {
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      return throwErrorMessage(error);
    } finally {
      if (isCurrentProjection($state, agentId, epoch))
        commit('SET_UI_FLAG', { resyncingItem: false });
    }
  },

  // Starts a single polling loop while any source is still ingesting; clears
  // itself once everything settles. Idempotent: never stacks timers.
  schedulePoll: (
    { dispatch, state: $state },
    { agentId, records = [], epoch } = {}
  ) => {
    const expectedEpoch = epoch ?? currentEpoch($state);
    if (
      pollTimer ||
      !records.some(isIngesting) ||
      !isCurrentProjection($state, agentId, expectedEpoch)
    )
      return;
    pollTimer = setTimeout(async () => {
      pollTimer = null;
      if (!isCurrentProjection($state, agentId, expectedEpoch)) return;
      await dispatch('fetch', { agentId, expectedEpoch });
    }, POLL_INTERVAL);
  },

  stopPolling: () => {
    clearPoll();
  },

  reset: ({ commit }) => {
    sourcesRequest.abort();
    clearPoll();
    commit('RESET');
  },
};

export const mutations = {
  SET_UI_FLAG($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  SET($state, records) {
    $state.records = records || [];
  },
  UPSERT($state, source) {
    $state.records = upsertItem($state.records || [], source);
  },
  DELETE($state, sourceId) {
    $state.records = ($state.records || []).filter(
      source => source.id !== sourceId
    );
  },
  BEGIN_PROJECTION($state, agentId) {
    $state.epoch = currentEpoch($state) + 1;
    $state.activeAgentId = agentId;
  },
  RESET($state) {
    $state.epoch = currentEpoch($state) + 1;
    $state.activeAgentId = null;
    $state.records = [];
    $state.uiFlags = {
      fetchingList: false,
      creatingItem: false,
      deletingItem: false,
      resyncingItem: false,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
