import { defineComponent, ref, computed } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import axios from 'axios';
import { useRelationships } from 'dashboard/composables/useRelationships';

const context = vi.hoisted(() => ({
  accountId: null,
  enabled: null,
  store: null,
  user: null,
}));
vi.mock('axios', () => ({ default: { get: vi.fn(), patch: vi.fn() } }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => context.store,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: context.accountId,
    currentAccount: computed(() => ({ id: context.accountId.value })),
    isCloudFeatureEnabled: () => context.enabled.value,
  }),
}));
const Probe = defineComponent({ setup: useRelationships, template: '<div />' });
const response = id => ({
  data: {
    configuration: { revision: 0, surfaces: {} },
    definitions: [{ id }],
    can_manage: true,
  },
});

beforeEach(() => {
  context.accountId = ref(801);
  context.enabled = ref(true);
  vi.clearAllMocks();
  context.user = ref(1);
  context.store = {
    commit: vi.fn(),
    subscribe: vi.fn(),
    getters: {
      get getCurrentUserID() {
        return context.user.value;
      },
    },
  };
});
it('never exposes a late response from another account', async () => {
  let first;
  axios.get.mockImplementation(url =>
    url.includes('/801/')
      ? new Promise(resolve => {
          first = resolve;
        })
      : Promise.resolve(response(2))
  );
  const wrapper = mount(Probe);
  context.accountId.value = 802;
  await flushPromises();
  expect(wrapper.vm.state.definitions).toEqual([{ id: 2 }]);
  first(response(1));
  await flushPromises();
  expect(wrapper.vm.state.definitions).toEqual([{ id: 2 }]);
  await expect(wrapper.vm.save({ revision: 0 }, 801)).rejects.toThrow(
    'Account changed'
  );
  expect(axios.patch).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('makes no relationship request when disabled', async () => {
  context.enabled.value = false;
  const wrapper = mount(Probe);
  await flushPromises();
  expect(axios.get).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('represents load errors separately from absent configuration and allows retry', async () => {
  context.accountId.value = 803;
  axios.get
    .mockRejectedValueOnce(new Error('offline'))
    .mockResolvedValueOnce(response(3));
  const wrapper = mount(Probe);
  await flushPromises();
  expect(wrapper.vm.state.error).toBe(true);
  expect(wrapper.vm.state.configuration).toBe(null);
  await wrapper.vm.load();
  expect(wrapper.vm.state.error).toBe(false);
  expect(wrapper.vm.state.definitions).toEqual([{ id: 3 }]);
  wrapper.unmount();
});

it('invalidates a pending read on save even at the same revision and syncs definitions once', async () => {
  axios.get.mockResolvedValue(response(1));
  const wrapper = mount(Probe);
  await flushPromises();
  let oldRead;
  axios.get.mockImplementation(
    () =>
      new Promise(resolve => {
        oldRead = resolve;
      })
  );
  const read = wrapper.vm.load();
  axios.patch.mockResolvedValue({
    data: {
      configuration: { revision: 1, surfaces: {} },
      definition: { id: 2 },
    },
  });
  await wrapper.vm.save({ revision: 0 }, 801);
  oldRead(response(9));
  await read;
  expect(wrapper.vm.state.definitions).toEqual([{ id: 1 }, { id: 2 }]);
  expect(context.store.commit).toHaveBeenLastCalledWith(
    'attributes/SET_CUSTOM_ATTRIBUTE',
    [{ id: 1 }, { id: 2 }]
  );
  wrapper.unmount();
});
it('drops management rights on user change and logout, then revalidates on focus', async () => {
  axios.get.mockResolvedValue(response(1));
  const wrapper = mount(Probe);
  await flushPromises();
  expect(wrapper.vm.state.can_manage).toBe(true);
  axios.get.mockResolvedValue({
    data: { ...response(2).data, can_manage: false },
  });
  context.user.value = 2;
  expect(wrapper.vm.state.can_manage).toBe(false);
  await flushPromises();
  expect(wrapper.vm.state.definitions).toEqual([{ id: 2 }]);
  axios.get.mockResolvedValue(response(3));
  window.dispatchEvent(new Event('focus'));
  await flushPromises();
  expect(wrapper.vm.state.definitions).toEqual([{ id: 3 }]);
  context.store.subscribe.mock.calls[0][0]({ type: 'CLEAR_USER' });
  context.user.value = null;
  expect(wrapper.vm.state.can_manage).toBe(false);
  expect(wrapper.vm.state.definitions).toEqual([]);
  wrapper.unmount();
});

it('completes a session read for the remaining surface when the initiating surface unmounts', async () => {
  let resolve;
  axios.get.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const first = mount(Probe);
  const second = mount(Probe);
  expect(axios.get).toHaveBeenCalledTimes(1);
  first.unmount();
  resolve(response(4));
  await flushPromises();
  expect(second.vm.state.definitions).toEqual([{ id: 4 }]);
  expect(second.vm.state.loading).toBe(false);
  second.unmount();
});

// Match the dashboard bootstrap: feature requests use the configured global client.
const originalDashboardClient = window.axios;
beforeEach(() => {
  window.axios = axios;
});
afterEach(() => {
  window.axios = originalDashboardClient;
});

it('preserves confirmed configuration and management on offline focus, then clears stale state on retry', async () => {
  axios.get.mockResolvedValueOnce(response(6));
  const wrapper = mount(Probe);
  await flushPromises();
  axios.get.mockRejectedValueOnce(new Error('offline'));
  window.dispatchEvent(new Event('focus'));
  await flushPromises();
  expect(wrapper.vm.state).toMatchObject({
    can_manage: true,
    error: true,
    stale: true,
    definitions: [{ id: 6 }],
  });
  axios.get.mockResolvedValueOnce(response(7));
  await wrapper.vm.load();
  expect(wrapper.vm.state).toMatchObject({
    can_manage: true,
    error: false,
    stale: false,
    definitions: [{ id: 7 }],
  });
  wrapper.unmount();
});

it.each([401, 403])(
  'clears confirmed privileges on a %s read and rejects local configuration writes',
  async status => {
    axios.get.mockResolvedValueOnce(response(6));
    const wrapper = mount(Probe);
    await flushPromises();
    axios.get.mockRejectedValueOnce({ response: { status } });
    await wrapper.vm.load();
    expect(wrapper.vm.state).toMatchObject({
      can_manage: false,
      error: true,
      definitions: [],
      configuration: null,
    });
    await expect(wrapper.vm.save({ revision: 0 }, 801)).rejects.toThrow(
      'Management unavailable'
    );
    expect(axios.patch).not.toHaveBeenCalled();
    wrapper.unmount();
  }
);

it.each([401, 403])(
  'revokes configuration access on a %s write without restoring a pending read',
  async status => {
    axios.get.mockResolvedValueOnce(response(6));
    const wrapper = mount(Probe);
    await flushPromises();
    let finishRead;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finishRead = resolve;
        })
    );
    const read = wrapper.vm.load();
    axios.patch.mockRejectedValueOnce({ response: { status } });
    await expect(wrapper.vm.save({ revision: 0 }, 801)).rejects.toEqual({
      response: { status },
    });
    finishRead(response(9));
    await read;
    expect(wrapper.vm.state.can_manage).toBe(false);
    expect(wrapper.vm.state.definitions).toEqual([]);
    wrapper.unmount();
  }
);
