import { mount, RouterLinkStub } from '@vue/test-utils';
import { ref } from 'vue';
import ContactOpportunityLink from '../ContactOpportunityLink.vue';

const accountId = ref(1);
const canViewCrm = ref(true);
const canManageCards = ref(true);
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId }),
}));
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canViewCrm, canManageCards }),
}));
let wrapper;
const render = () =>
  mount(ContactOpportunityLink, {
    props: { contactId: 42 },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
beforeEach(() => {
  window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  accountId.value = 1;
  canViewCrm.value = true;
  canManageCards.value = true;
});
afterEach(() => wrapper?.unmount());

it('opens the CRM intent in a new tab without putting contact data in the URL', () => {
  wrapper = render();
  const link = wrapper.findComponent(RouterLinkStub);
  expect(link.props('to')).toEqual({
    name: 'crm_kanban_index',
    params: { accountId: 1 },
    query: { new_contact_id: '42' },
  });
  expect(link.attributes('target')).toBe('_blank');
  expect(link.attributes('rel')).toBe('noopener noreferrer');
  expect(link.attributes('aria-label')).toContain('OPEN_NEW_TAB');
});
it('updates the destination when another account or contact is displayed', async () => {
  wrapper = render();
  accountId.value = 2;
  await wrapper.setProps({ contactId: 51 });
  expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
    name: 'crm_kanban_index',
    params: { accountId: 2 },
    query: { new_contact_id: '51' },
  });
});
it('hides the action for CRM view-only users', () => {
  canManageCards.value = false;
  wrapper = render();
  expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
});
it('hides the action when CRM view access is absent', () => {
  canViewCrm.value = false;
  wrapper = render();
  expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
});
it('hides the action when the installation has CRM disabled', () => {
  window.globalConfig.CRM_KANBAN_ENABLED = 'false';
  wrapper = render();
  expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
});
