import { shallowMount } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ContactAPI from 'dashboard/api/contacts';
import { useAlert } from 'dashboard/composables';
import CrmCardAutoFollowupStatus from './CrmCardAutoFollowupStatus.vue';
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
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
it.each([
  ['kept_no_permission', 'RESET_KEPT_NO_PERMISSION'],
  ['kept_other_cards', 'RESET_KEPT_OTHER_CARDS'],
  ['kept_other_source', 'RESET_KEPT_OTHER_SOURCE'],
  ['released', 'RESET_SUCCESS'],
  [undefined, 'RESET_SUCCESS'],
])(
  'reset with contact opt-out %s shows the matching alert',
  async (result, key) => {
    CrmKanbanAPI.resetAutoFollowup.mockResolvedValueOnce({
      data: { contact_opt_out: result },
    });
    const wrapper = shallowMount(CrmCardAutoFollowupStatus, {
      props: { card, canManageAi: true },
    });
    await wrapper.vm.resetCycle();
    expect(useAlert).toHaveBeenCalledWith(
      `CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.${key}`
    );
    wrapper.unmount();
  }
);
it('shows the cadence as turned off when it stopped because the contact left the AI follow-up (#2084)', () => {
  const parado = {
    ...card,
    auto_followup: {
      spent: false,
      stopped_reason: 'contact_disabled',
      max_touches: 3,
      touches: [{ outcome: 'sent' }],
    },
  };
  const wrapper = shallowMount(CrmCardAutoFollowupStatus, {
    props: { card: parado },
  });
  expect(wrapper.text()).toContain(
    'CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_CONTACT_DISABLED'
  );
  wrapper.unmount();
});
