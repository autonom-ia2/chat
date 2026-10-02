import { shallowMount } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ContactAPI from 'dashboard/api/contacts';
import CrmCardAutoFollowupStatus from './CrmCardAutoFollowupStatus.vue';
vi.mock('dashboard/api/crmKanban', () => ({
  default: { resetAutoFollowup: vi.fn().mockResolvedValue({}) },
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { update: vi.fn().mockResolvedValue({}) },
}));
const card = {
  id: 5,
  contact: { id: 12, additional_attributes: {} },
  auto_followup: {
    spent: true,
    stopped_reason: 'max_touches',
    max_touches: 3,
    touches: [],
  },
};
beforeEach(() => vi.clearAllMocks());
it('allows reading cadence but not resetting or changing the contact by default', async () => {
  const wrapper = shallowMount(CrmCardAutoFollowupStatus, { props: { card } });
  expect(wrapper.text()).toContain(
    'CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_DONE'
  );
  expect(wrapper.findComponent({ name: 'Button' }).exists()).toBe(false);
  // disabled is a native attribute on Switch's button, not a declared prop.
  expect(wrapper.findComponent({ name: 'Switch' }).attributes('disabled')).toBe(
    'true'
  );
  await wrapper.vm.resetCycle();
  await wrapper.vm.onContactToggle(true);
  expect(CrmKanbanAPI.resetAutoFollowup).not.toHaveBeenCalled();
  expect(ContactAPI.update).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('does not grant shared-contact writes from AI management', async () => {
  const wrapper = shallowMount(CrmCardAutoFollowupStatus, {
    props: { card, canManageAi: true },
  });
  await wrapper.vm.resetCycle();
  await wrapper.vm.onContactToggle(true);
  expect(CrmKanbanAPI.resetAutoFollowup).toHaveBeenCalledWith(5);
  expect(ContactAPI.update).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('does not grant AI reset from shared-contact management', async () => {
  const wrapper = shallowMount(CrmCardAutoFollowupStatus, {
    props: { card, canManageRecords: true },
  });
  await wrapper.vm.onContactToggle(true);
  await wrapper.vm.resetCycle();
  expect(ContactAPI.update).toHaveBeenCalledWith(12, {
    additional_attributes: { crm_ai_followup_disabled: true },
  });
  expect(CrmKanbanAPI.resetAutoFollowup).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('rechecks both capabilities for stale actions after revocation', async () => {
  const wrapper = shallowMount(CrmCardAutoFollowupStatus, {
    props: { card, canManageRecords: true, canManageAi: true },
  });
  await wrapper.setProps({ canManageRecords: false, canManageAi: false });
  await wrapper.vm.resetCycle();
  await wrapper.vm.onContactToggle(true);
  expect(CrmKanbanAPI.resetAutoFollowup).not.toHaveBeenCalled();
  expect(ContactAPI.update).not.toHaveBeenCalled();
  wrapper.unmount();
});
