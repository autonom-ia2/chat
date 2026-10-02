import { effectScope, ref, nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useContactOpportunities } from '../useContactOpportunities';

vi.mock('dashboard/api/crmKanban', () => ({
  default: { getContactOpportunities: vi.fn() },
}));
const payload = {
  data: {
    payload: [{ id: 10, title: 'Opportunity' }],
    meta: { total_count: 7, page: 1, has_more: true },
  },
};
let scope;
let controller;
let accountId;
let contactId;
let enabled;
beforeEach(() => {
  vi.clearAllMocks();
  CrmKanbanAPI.getContactOpportunities.mockResolvedValue(payload);
  accountId = ref(1);
  contactId = ref(42);
  enabled = ref(false);
  scope = effectScope();
  scope.run(() => {
    controller = useContactOpportunities({ accountId, contactId, enabled });
  });
});
afterEach(() => scope.stop());

it('does not query while the tab or permission gate is inactive', async () => {
  await controller.load();
  expect(CrmKanbanAPI.getContactOpportunities).not.toHaveBeenCalled();
});
it('queries one server page with a signal and no board-state filters when enabled', async () => {
  enabled.value = true;
  await flushPromises();
  expect(CrmKanbanAPI.getContactOpportunities).toHaveBeenCalledTimes(1);
  expect(CrmKanbanAPI.getContactOpportunities).toHaveBeenCalledWith(
    42,
    { page: 1, result: 'active', search: '' },
    { signal: expect.any(AbortSignal) }
  );
  expect(controller.state.items).toEqual(payload.data.payload);
  expect(controller.state.total).toBe(7);
});
it('paginates on the server instead of slicing local cached board rows', async () => {
  enabled.value = true;
  await flushPromises();
  await controller.load(2);
  expect(CrmKanbanAPI.getContactOpportunities.mock.lastCall[1].page).toBe(2);
});
it('only applies search on explicit confirmation and resets its page', async () => {
  enabled.value = true;
  await flushPromises();
  controller.state.query = '  Renewals  ';
  await nextTick();
  expect(CrmKanbanAPI.getContactOpportunities).toHaveBeenCalledTimes(1);
  await controller.apply();
  expect(CrmKanbanAPI.getContactOpportunities.mock.lastCall[1]).toMatchObject({
    page: 1,
    search: 'Renewals',
  });
});
it('changes status with the confirmed search without silently submitting unfinished typing', async () => {
  enabled.value = true;
  await flushPromises();
  controller.state.search = 'confirmed';
  controller.state.query = 'not submitted';
  await controller.setResult('won');
  expect(CrmKanbanAPI.getContactOpportunities.mock.lastCall[1]).toEqual({
    page: 1,
    result: 'won',
    search: 'confirmed',
  });
});
it('clears old account rows, count and filters immediately and rejects late responses', async () => {
  let finish;
  enabled.value = true;
  await flushPromises();
  CrmKanbanAPI.getContactOpportunities.mockReturnValueOnce(
    new Promise(done => {
      finish = done;
    })
  );
  const previous = controller.load();
  controller.state.query = 'Old account';
  accountId.value = 2;
  expect(controller.state.items).toEqual([]);
  expect(controller.state.total).toBe(0);
  expect(controller.state.query).toBe('');
  await flushPromises();
  finish({
    data: {
      payload: [{ id: 99, title: 'Old private result' }],
      meta: { total_count: 100, page: 1, has_more: false },
    },
  });
  await previous;
  expect(controller.state.items).toEqual(payload.data.payload);
  expect(controller.state.total).toBe(7);
});
it('clears a revoked or inactive view synchronously and cannot reapply a late response', async () => {
  let finish;
  CrmKanbanAPI.getContactOpportunities.mockReturnValue(
    new Promise(done => {
      finish = done;
    })
  );
  enabled.value = true;
  const signal = CrmKanbanAPI.getContactOpportunities.mock.lastCall[2].signal;
  enabled.value = false;
  expect(signal.aborted).toBe(true);
  finish(payload);
  await flushPromises();
  expect(controller.state.loaded).toBe(false);
  expect(controller.state.items).toEqual([]);
});
it('resets the query and page when the contact changes', async () => {
  enabled.value = true;
  await flushPromises();
  controller.state.result = 'won';
  controller.state.query = 'Old';
  controller.state.page = 5;
  contactId.value = 88;
  await flushPromises();
  expect(CrmKanbanAPI.getContactOpportunities.mock.lastCall[0]).toBe(88);
  expect(CrmKanbanAPI.getContactOpportunities.mock.lastCall[1]).toEqual({
    page: 1,
    result: 'active',
    search: '',
  });
});
it('shows a failed request instead of a misleading empty successful result and allows retry', async () => {
  CrmKanbanAPI.getContactOpportunities.mockRejectedValueOnce(
    new Error('Offline')
  );
  enabled.value = true;
  await flushPromises();
  expect(controller.state.failed).toBe(true);
  expect(controller.state.loaded).toBe(false);
  await controller.load();
  expect(controller.state.failed).toBe(false);
  expect(controller.state.loaded).toBe(true);
});
it('refreshes when the operator returns from a CRM tab without clearing the search draft', async () => {
  enabled.value = true;
  await flushPromises();
  controller.state.query = 'Unsubmitted text';
  window.dispatchEvent(new Event('focus'));
  await flushPromises();
  expect(CrmKanbanAPI.getContactOpportunities).toHaveBeenCalledTimes(2);
  expect(controller.state.query).toBe('Unsubmitted text');
});
it('stops requests and focus listeners when the profile is disposed', async () => {
  enabled.value = true;
  await flushPromises();
  scope.stop();
  window.dispatchEvent(new Event('focus'));
  await flushPromises();
  expect(CrmKanbanAPI.getContactOpportunities).toHaveBeenCalledTimes(1);
});
