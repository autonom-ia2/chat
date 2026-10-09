import AutonomiaChannelsAPI from '../../api/autonomia/channels';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const channelsRequest = useAbortableRequest();

const currentEpoch = $state => $state?.epoch ?? 0;
const isCurrentProjection = ($state, agentId, epoch) =>
  $state?.activeAgentId === agentId && currentEpoch($state) === epoch;

const throwPreservingApiError = error => {
  const response = error?.response;
  const responseData = response?.data;
  const message =
    responseData?.message ||
    responseData?.error ||
    error?.message ||
    'Request failed';
  const raised = error instanceof Error ? error : new Error(message);
  if (responseData?.message && raised.message !== responseData.message)
    raised.message = responseData.message;
  if (response) raised.response = response;
  if (response?.status != null) raised.status = response.status;
  const code = responseData?.code || responseData?.error_code || error?.code;
  if (code) raised.code = code;
  throw raised;
};

const beginProjection = (commit, $state, agentId) => {
  channelsRequest.abort();
  commit('BEGIN_PROJECTION', agentId);
  return currentEpoch($state);
};

const ensureAgentProjection = (commit, $state, agentId) => {
  if ($state.activeAgentId === agentId) return currentEpoch($state);
  return beginProjection(commit, $state, agentId);
};

// Per-agent channel connections. `fetch` returns both the connected inboxes and
// the eligible ones (each inbox can host only one agent), kept as two lists so
// the Channels tab can render connect/disconnect affordances directly.
export const state = {
  epoch: 0,
  activeAgentId: null,
  connected: [],
  eligible: [],
  uiFlags: {
    fetching: false,
    connecting: false,
    disconnecting: false,
  },
};

export const getters = {
  getConnected($state) {
    return $state.connected;
  },
  getEligible($state) {
    return $state.eligible;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  fetch: async ({ commit, state: $state }, { agentId } = {}) => {
    if (!agentId) return null;
    const epoch = beginProjection(commit, $state, agentId);
    // Zera as listas antes de buscar (store module-wide): ao trocar de agente,
    // sem isto os canais do agente anterior ficam visíveis até o fetch voltar,
    // com botões conectar/desconectar apontando pro agente novo.
    commit('SET_CHANNELS', { connected: [], eligible: [] });
    commit('SET_UI_FLAG', {
      fetching: true,
      connecting: false,
      disconnecting: false,
    });
    try {
      const response = await channelsRequest.run(signal =>
        AutonomiaChannelsAPI.get(agentId, { signal })
      );
      if (!response || !isCurrentProjection($state, agentId, epoch))
        return null;
      const { data } = response;
      // Backend shape: `payload` is the array of connected agent-inboxes, and
      // `eligible_inboxes` is a sibling key with the connectable inboxes.
      commit('SET_CHANNELS', {
        connected: data.payload || [],
        eligible: data.eligible_inboxes || [],
      });
      return data;
    } catch (error) {
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      return throwPreservingApiError(error);
    } finally {
      if (isCurrentProjection($state, agentId, epoch))
        commit('SET_UI_FLAG', { fetching: false });
    }
  },

  connect: async (
    { commit, dispatch, state: $state },
    { agentId, inboxId }
  ) => {
    const epoch = ensureAgentProjection(commit, $state, agentId);
    commit('SET_UI_FLAG', { connecting: true });
    let connected = false;
    try {
      const { data } = await AutonomiaChannelsAPI.connect(agentId, inboxId);
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      connected = true;
      // Re-sync from server truth: a connect moves the inbox between the
      // eligible and connected lists and may free/occupy others.
      await dispatch('fetch', { agentId });
      return data.payload || data;
    } catch (error) {
      // Só propaga quando o CONNECT em si falhou. Se o vínculo foi criado e
      // apenas o refetch caiu, lançar aqui faria o chamador (PanelPublish/
      // Builder) desativar o agente por engano — deixando canal conectado a
      // agente inativo.
      if (connected) return null;
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      return throwErrorMessage(error);
    } finally {
      if (isCurrentProjection($state, agentId, epoch))
        commit('SET_UI_FLAG', { connecting: false });
    }
  },

  disconnect: async (
    { commit, dispatch, state: $state },
    { agentId, inboxId }
  ) => {
    const epoch = ensureAgentProjection(commit, $state, agentId);
    commit('SET_UI_FLAG', { disconnecting: true });
    try {
      await AutonomiaChannelsAPI.disconnect(agentId, inboxId);
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      await dispatch('fetch', { agentId });
      return inboxId;
    } catch (error) {
      if (!isCurrentProjection($state, agentId, epoch)) return null;
      return throwErrorMessage(error);
    } finally {
      if (isCurrentProjection($state, agentId, epoch))
        commit('SET_UI_FLAG', { disconnecting: false });
    }
  },

  reset: ({ commit }) => {
    channelsRequest.abort();
    commit('RESET');
  },
};

export const mutations = {
  SET_UI_FLAG($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  SET_CHANNELS($state, { connected, eligible }) {
    $state.connected = connected || [];
    $state.eligible = eligible || [];
  },
  BEGIN_PROJECTION($state, agentId) {
    $state.epoch = currentEpoch($state) + 1;
    $state.activeAgentId = agentId;
  },
  RESET($state) {
    $state.epoch = currentEpoch($state) + 1;
    $state.activeAgentId = null;
    $state.connected = [];
    $state.eligible = [];
    $state.uiFlags = {
      fetching: false,
      connecting: false,
      disconnecting: false,
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
