import { computed, ref } from 'vue';

import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';

const STATE_CODES = new Set(['E1', 'E2', 'E2m', 'E3', 'E4', 'E5', 'E6']);

const responsePayload = response => {
  const payload = response?.data?.payload ?? response?.payload;
  if (!Array.isArray(payload)) throw new Error('agents_list_invalid_payload');

  payload.forEach(agent => {
    if (!STATE_CODES.has(agent?.state?.code)) {
      throw new Error('agents_list_invalid_state');
    }
  });

  return payload;
};

export function useAgentsList() {
  const rows = ref([]);
  const status = ref('idle');
  const error = ref(null);
  const isStale = ref(false);
  const { run, abort } = useAbortableRequest();

  const load = async ({ staleOnError = false } = {}) => {
    status.value = 'loading';
    error.value = null;

    try {
      const response = await run(signal => AutonomiaAgentsAPI.get({ signal }));
      // A superseded request is deliberately invisible to the state machine.
      if (!response) return null;

      const nextRows = responsePayload(response);
      rows.value = nextRows;
      status.value = 'success';
      isStale.value = false;
      return nextRows;
    } catch (requestError) {
      if (isAbortError(requestError)) return null;
      error.value = requestError;
      status.value = 'error';
      isStale.value = staleOnError;
      return null;
    }
  };

  const updateStatus = async (agent, { status: nextStatus, enabled }) => {
    await AutonomiaAgentsAPI.update(agent.id, {
      status: nextStatus,
      enabled,
    });
    return load({ staleOnError: true });
  };

  const deleteDraft = async agent => {
    await AutonomiaAgentsAPI.delete(agent.id);
    return load({ staleOnError: true });
  };

  return {
    rows,
    status,
    error,
    isStale,
    isLoading: computed(() => status.value === 'loading'),
    load,
    retry: load,
    updateStatus,
    deleteDraft,
    abort,
  };
}
