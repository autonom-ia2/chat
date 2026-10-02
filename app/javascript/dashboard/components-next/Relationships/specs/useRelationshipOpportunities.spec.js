import { effectScope, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useRelationshipOpportunities } from '../useRelationshipOpportunities';

let scope;
let controller;
let recordId;
let enabled;
let accountId;
let fetchOpportunities;
const response = {
  data: {
    payload: [{ id: 1, contact: { id: 12, name: 'Person' } }],
    meta: { total_count: 1, has_more: false, page: 1 },
  },
};
beforeEach(() => {
  scope = effectScope();
  recordId = ref(7);
  accountId = ref(1);
  enabled = ref(false);
  fetchOpportunities = vi.fn().mockResolvedValue(response);
  scope.run(() => {
    controller = useRelationshipOpportunities({
      accountId,
      recordId,
      enabled,
      fetchOpportunities,
    });
  });
});
afterEach(() => scope.stop());

it('does not load before the company tab and feature permissions are enabled', async () => {
  await controller.load();
  expect(fetchOpportunities).not.toHaveBeenCalled();
  enabled.value = true;
  await flushPromises();
  expect(fetchOpportunities).toHaveBeenCalledOnce();
  expect(fetchOpportunities).toHaveBeenCalledWith(
    7,
    { page: 1, result: 'active', search: '' },
    { signal: expect.any(AbortSignal) }
  );
});
it('drops old-company responses and clears counts, search and page on company navigation', async () => {
  enabled.value = true;
  await flushPromises();
  let finish;
  fetchOpportunities.mockReturnValueOnce(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  const pending = controller.load();
  controller.state.query = 'Old company';
  controller.state.page = 9;
  recordId.value = 8;
  expect(controller.state.total).toBe(0);
  expect(controller.state.query).toBe('');
  await flushPromises();
  finish({
    data: {
      payload: [{ id: 999 }],
      meta: { total_count: 999, page: 1, has_more: false },
    },
  });
  await pending;
  expect(controller.state.items).toEqual(response.data.payload);
  expect(fetchOpportunities.mock.lastCall[0]).toBe(8);
  expect(controller.state.page).toBe(1);
});
it('clears results on feature or permission loss and aborts the active request', async () => {
  let finish;
  fetchOpportunities.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  enabled.value = true;
  const signal = fetchOpportunities.mock.lastCall[2].signal;
  enabled.value = false;
  finish(response);
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(controller.state.items).toEqual([]);
  expect(controller.state.total).toBe(0);
});
it('keeps draft search separate from confirmed filters and re-reads on focus', async () => {
  enabled.value = true;
  await flushPromises();
  controller.setQuery('  Confirmed  ');
  await controller.apply();
  controller.setQuery('Draft');
  await controller.setResult('won');
  window.dispatchEvent(new Event('focus'));
  await flushPromises();
  expect(fetchOpportunities.mock.lastCall[1]).toEqual({
    page: 1,
    search: 'Confirmed',
    result: 'won',
  });
  expect(controller.state.query).toBe('Draft');
});
it('reports errors separately from empty results and allows a real reload', async () => {
  fetchOpportunities.mockRejectedValueOnce(new Error('Offline'));
  enabled.value = true;
  await flushPromises();
  expect(controller.state.failed).toBe(true);
  expect(controller.state.loaded).toBe(false);
  await controller.load();
  expect(controller.state.failed).toBe(false);
  expect(controller.state.items).toEqual(response.data.payload);
});
it('stops focus refreshes after unmount', async () => {
  enabled.value = true;
  await flushPromises();
  scope.stop();
  window.dispatchEvent(new Event('focus'));
  expect(fetchOpportunities).toHaveBeenCalledOnce();
});
