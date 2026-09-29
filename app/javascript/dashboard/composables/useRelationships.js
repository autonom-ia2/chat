import { computed, reactive, watch, onBeforeUnmount } from 'vue';
import { useEventListener } from '@vueuse/core';
import axios from 'dashboard/api/relationships';
import { useStore } from './store';
import { useAccount } from './useAccount';

// A store belongs to one application session. CLEAR_USER also invalidates pending work.
const sessions = new WeakMap();
const emptyState = () => ({
  configuration: null,
  definitions: [],
  can_manage: false,
  error: false,
  stale: false,
  loading: false,
});
const sessionFor = store => {
  if (!sessions.has(store)) {
    const session = { entries: reactive({}), pending: new Map() };
    store.subscribe(mutation => {
      if (mutation.type === 'CLEAR_USER') {
        Object.keys(session.entries).forEach(key => {
          delete session.entries[key];
        });
        session.pending.clear();
      }
    });
    sessions.set(store, session);
  }
  return sessions.get(store);
};

export function useRelationships() {
  const store = useStore();
  const session = sessionFor(store);
  const { accountId, currentAccount, isCloudFeatureEnabled } = useAccount();
  const userId = computed(() => store.getters.getCurrentUserID);
  const enabled = name =>
    computed(() =>
      Boolean(
        currentAccount.value?.id &&
          isCloudFeatureEnabled(`relationships_${name}`)
      )
    );
  const attributesEnabled = computed(() =>
    Boolean(
      userId.value &&
        currentAccount.value?.id &&
        isCloudFeatureEnabled('custom_attributes') &&
        isCloudFeatureEnabled('relationships_attributes')
    )
  );
  const navigationEnabled = enabled('navigation');
  const companiesEnabled = computed(() =>
    Boolean(currentAccount.value?.id && isCloudFeatureEnabled('companies'))
  );
  const mediaEnabled = computed(
    () =>
      companiesEnabled.value &&
      isCloudFeatureEnabled('relationships_company_media')
  );
  const key = computed(() => `${userId.value}:${accountId.value}`);
  const state = computed(() =>
    attributesEnabled.value
      ? session.entries[key.value]?.state || emptyState()
      : emptyState()
  );
  const url = id => `/api/v1/accounts/${id}/relationships/configuration`;
  let context = 0;
  let disposed = false;

  const load = async () => {
    if (!attributesEnabled.value || disposed) return undefined;
    const identity = key.value;
    const id = accountId.value;
    session.entries[identity] ||= { state: emptyState(), generation: 0 };
    const entry = session.entries[identity];
    if (session.pending.has(identity)) return session.pending.get(identity);
    const generation = entry.generation;
    const storeRevision = store.getters['attributes/getRevision'];
    let staleDefinitions = false;
    const current = context;
    // The shared read belongs to the session, even if its initiating component unmounts.
    const valid = () =>
      current === context &&
      identity === key.value &&
      session.entries[identity] === entry &&
      entry.generation === generation;
    entry.state.loading = true;
    entry.state.error = false;
    const request = axios
      .get(url(id))
      .then(({ data }) => {
        if (!valid()) return;
        if (storeRevision !== store.getters['attributes/getRevision']) {
          staleDefinitions = true;
          return;
        }
        Object.assign(entry.state, data, { error: false, stale: false });
        store.commit('attributes/SET_CUSTOM_ATTRIBUTE', data.definitions);
      })
      .catch(error => {
        if (!valid()) return;
        if ([401, 403].includes(error.response?.status)) {
          Object.assign(entry.state, emptyState(), { error: true });
          entry.generation += 1;
        } else {
          Object.assign(entry.state, { error: true, stale: true });
        }
      })
      .finally(() => {
        if (valid()) entry.state.loading = false;
        if (session.pending.get(identity) === request)
          session.pending.delete(identity);
        if (staleDefinitions && valid()) return load();
        return undefined;
      });
    session.pending.set(identity, request);
    return request;
  };

  const save = async (payload, expectedAccountId) => {
    if (accountId.value !== expectedAccountId || !attributesEnabled.value)
      throw new Error('Account changed');
    const identity = key.value;
    const current = context;
    const entry = session.entries[identity];
    if (!entry?.state.can_manage) throw new Error('Management unavailable');
    // Invalidate reads started before this write, even if the configuration revision is equal.
    entry.generation += 1;
    session.pending.delete(identity);
    entry.state.loading = false;
    const generation = entry.generation;
    let data;
    try {
      ({ data } = await axios.patch(url(expectedAccountId), {
        configuration: payload,
      }));
    } catch (error) {
      if (
        current === context &&
        identity === key.value &&
        session.entries[identity] === entry &&
        entry.generation === generation &&
        [401, 403].includes(error.response?.status)
      ) {
        entry.generation += 1;
        Object.assign(entry.state, emptyState(), { error: true });
      }
      throw error;
    }
    if (
      disposed ||
      current !== context ||
      identity !== key.value ||
      session.entries[identity] !== entry ||
      entry.generation !== generation
    )
      return data;
    if (data.configuration.revision < entry.state.configuration.revision)
      return data;
    entry.generation += 1;
    session.pending.delete(identity);
    entry.state.configuration = data.configuration;
    entry.state.error = false;
    entry.state.stale = false;
    if (data.definition)
      entry.state.definitions = entry.state.definitions
        .filter(item => item.id !== data.definition.id)
        .concat(data.definition);
    store.commit('attributes/SET_CUSTOM_ATTRIBUTE', entry.state.definitions);
    return data;
  };

  watch(
    [key, attributesEnabled, companiesEnabled],
    (_next, previous) => {
      context += 1;
      if (previous?.[0]) {
        delete session.entries[previous[0]];
        session.pending.delete(previous[0]);
      }
      load();
    },
    { immediate: true, flush: 'sync' }
  );
  useEventListener(window, 'focus', load);
  onBeforeUnmount(() => {
    disposed = true;
  });
  return {
    accountId,
    attributesEnabled,
    navigationEnabled,
    mediaEnabled,
    companiesEnabled,
    state,
    load,
    save,
  };
}
