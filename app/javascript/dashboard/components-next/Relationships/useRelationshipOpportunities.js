import { reactive, watch } from 'vue';
import { useEventListener } from '@vueuse/core';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';

// One controller belongs to the profile, shared by its desktop and mobile panels.
// It never populates the board store or reads that store's filters/pagination.
export function useRelationshipOpportunities({
  accountId,
  recordId,
  enabled,
  fetchOpportunities,
}) {
  const request = useAbortableRequest();
  const state = reactive({
    items: [],
    total: 0,
    page: 1,
    hasMore: false,
    result: 'active',
    query: '',
    search: '',
    failed: false,
    loaded: false,
  });
  const clearRows = () => {
    state.items = [];
    state.total = 0;
    state.hasMore = false;
    state.loaded = false;
  };
  const load = async (page = state.page) => {
    if (!enabled.value || !recordId.value) return;
    clearRows();
    state.failed = false;
    state.page = page;
    try {
      const response = await request.run(signal =>
        fetchOpportunities(
          recordId.value,
          {
            page,
            result: state.result,
            search: state.search,
          },
          { signal }
        )
      );
      if (!response) return;
      state.items = response.data.payload;
      state.total = response.data.meta.total_count;
      state.hasMore = response.data.meta.has_more;
      state.page = response.data.meta.page;
      state.loaded = true;
    } catch {
      state.failed = true;
    }
  };
  const apply = () => {
    state.search = state.query.trim();
    return load(1);
  };
  const setResult = result => {
    state.result = result;
    return load(1);
  };
  watch(
    [accountId, recordId, enabled],
    (next, previous = []) => {
      request.abort();
      clearRows();
      state.failed = false;
      if (next[0] !== previous[0] || next[1] !== previous[1]) {
        Object.assign(state, {
          page: 1,
          result: 'active',
          query: '',
          search: '',
        });
      }
      if (next[2]) load();
    },
    { immediate: true, flush: 'sync' }
  );
  // Returning from a CRM tab fetches the current authorized data, not stale rows.
  useEventListener(window, 'focus', () => {
    if (enabled.value && !request.isPending.value) load();
  });
  const setQuery = value => {
    state.query = value;
  };
  return {
    state,
    loading: request.isPending,
    load,
    apply,
    setResult,
    setQuery,
  };
}
