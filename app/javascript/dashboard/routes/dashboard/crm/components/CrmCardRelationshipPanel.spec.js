import { mount, flushPromises } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import CompanyAPI from 'dashboard/api/companies';
import CrmCardRelationshipPanel from './CrmCardRelationshipPanel.vue';

const routing = vi.hoisted(() => ({
  resolve: vi.fn(() => ({ href: '/resolved-profile' })),
}));
vi.mock('vue-router', () => ({ useRouter: () => routing }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: { value: 1 },
    currentAccount: { value: { id: 1 } },
    isCloudFeatureEnabled: () => true,
  }),
}));
vi.mock('dashboard/api/contacts', () => ({ default: { show: vi.fn() } }));
vi.mock('dashboard/api/companies', () => ({ default: { show: vi.fn() } }));
const person = {
  id: 42,
  name: 'Mariana',
  email: 'mariana@example.com',
  company_id: 7,
  additional_attributes: { city: 'Belo Horizonte' },
  custom_attributes: { job_title: 'Gerente' },
};
const makePanel = (props = {}) =>
  mount(CrmCardRelationshipPanel, {
    props: { card: { id: 5, contact_id: 42 }, canManage: true, ...props },
    global: { stubs: { Avatar: true, CrmRelationshipLinkForm: true } },
  });
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  ContactAPI.show.mockResolvedValue({ data: { payload: person } });
  CompanyAPI.show.mockResolvedValue({
    data: {
      payload: {
        id: 7,
        name: 'Canonical Company',
        domain: 'canonical.example',
      },
    },
  });
});
afterEach(() => {
  wrapper?.unmount();
});

it('loads the canonical contact and company, not the stale card snapshot', async () => {
  wrapper = makePanel({
    card: { id: 5, contact_id: 42, contact: { id: 42, name: 'Old snapshot' } },
  });
  await flushPromises();
  expect(ContactAPI.show).toHaveBeenCalledWith(42);
  expect(CompanyAPI.show).toHaveBeenCalledWith(7);
  expect(wrapper.text()).toContain('Mariana');
  expect(wrapper.text()).toContain('Canonical Company');
  expect(wrapper.text()).not.toContain('Old snapshot');
});
it('shows an actionable empty state without making a contact request', async () => {
  wrapper = makePanel({ card: { id: 5 } });
  await flushPromises();
  expect(ContactAPI.show).not.toHaveBeenCalled();
  expect(wrapper.find('[data-relationship-empty]').exists()).toBe(true);
  expect(wrapper.find('[data-relationship-company]').exists()).toBe(false);
});
it('does not offer mutations to a read-only viewer', async () => {
  wrapper = makePanel({ canManage: false, card: { id: 5 } });
  await flushPromises();
  expect(wrapper.findAll('button')).toHaveLength(0);
});
it('does not infer a company association from legacy text', async () => {
  ContactAPI.show.mockResolvedValue({
    data: {
      payload: {
        ...person,
        company_id: null,
        additional_attributes: { company_name: 'Legacy text' },
      },
    },
  });
  wrapper = makePanel();
  await flushPromises();
  expect(CompanyAPI.show).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain('LEGACY_COMPANY');
  expect(wrapper.text()).toContain('Legacy text');
});
it('keeps the contact visible when the company cannot be read', async () => {
  CompanyAPI.show.mockRejectedValue(new Error('not available'));
  wrapper = makePanel();
  await flushPromises();
  expect(wrapper.text()).toContain('Mariana');
  expect(wrapper.text()).toContain('COMPANY_UNAVAILABLE');
  expect(wrapper.text()).not.toContain('Canonical Company');
});
it('shows load failure instead of pretending the contact is absent', async () => {
  ContactAPI.show.mockRejectedValue(new Error('read failed'));
  wrapper = makePanel();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.find('[data-relationship-empty]').exists()).toBe(false);
});
it('drops a late response after switching the selected card', async () => {
  let resolveOld;
  ContactAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  wrapper = makePanel();
  await wrapper.setProps({ card: { id: 6, contact_id: 43 } });
  await flushPromises();
  ContactAPI.show.mockResolvedValue({
    data: { payload: { id: 43, name: 'New contact' } },
  });
  await wrapper.vm.reload();
  resolveOld({ data: { payload: { id: 42, name: 'Old contact' } } });
  await flushPromises();
  expect(wrapper.text()).toContain('New contact');
  expect(wrapper.text()).not.toContain('Old contact');
});
it('opens the actual profile in another tab while keeping the card context', async () => {
  const open = vi.spyOn(window, 'open').mockImplementation(() => null);
  wrapper = makePanel();
  await flushPromises();
  await wrapper.vm.openProfile('company');
  expect(routing.resolve).toHaveBeenCalledWith({
    name: 'companies_dashboard_show',
    params: { accountId: 1, companyId: 7 },
  });
  expect(open).toHaveBeenCalledWith(
    '/resolved-profile',
    '_blank',
    'noopener,noreferrer'
  );
  open.mockRestore();
});
it('emits the freshly loaded person when editing, not the old card snapshot', async () => {
  wrapper = makePanel();
  await flushPromises();
  const button = wrapper
    .findAll('button')
    .find(item => item.text() === 'CRM_KANBAN.RELATIONSHIP.EDIT');
  await button.trigger('click');
  expect(wrapper.emitted('edit')[0][0]).toEqual(person);
});
