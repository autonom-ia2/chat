import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createPinia, setActivePinia } from 'pinia';
import { mutations } from 'dashboard/store/modules/contacts/mutations';
import { getters } from 'dashboard/store/modules/contacts/getters';
import { useCompaniesStore } from 'dashboard/stores/companies';
import ContactAPI from 'dashboard/api/contacts';
import CompanyAPI from 'dashboard/api/companies';
import CrmCardRelationshipPanel from './CrmCardRelationshipPanel.vue';

const context = vi.hoisted(() => ({ store: null }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => context.store,
}));
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
    props: {
      card: { id: 5, contact_id: 42 },
      canManage: true,
      canManageRecords: props.canManage ?? true,
      onGuard: action => action(),
      ...props,
    },
    global: {
      stubs: {
        Avatar: true,
        CrmRelationshipLinkForm: true,
        CrmRelationshipResources: true,
      },
    },
  });
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  setActivePinia(createPinia());
  context.store = createStore({
    modules: {
      contacts: {
        namespaced: true,
        state: () => ({ records: {}, sortOrder: [] }),
        getters,
        mutations,
      },
    },
  });
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
  expect(wrapper.text()).toContain('LEGACY_COMPANY_NAME');
  expect(
    context.store.getters['contacts/getContact'](42).additional_attributes
      .company_name
  ).toBe('Legacy text');
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

it('reflects confirmed native store writes without a stale copy of the contact', async () => {
  wrapper = makePanel();
  await flushPromises();
  context.store.commit('contacts/SET_CONTACT_ITEM', {
    id: 42,
    custom_attributes: { job_title: 'Updated role' },
  });
  await wrapper.vm.$nextTick();
  expect(wrapper.text()).toContain('Updated role');
});
it('binds company custom values to the same Pinia record used in the company profile', async () => {
  wrapper = makePanel();
  await flushPromises();
  const companies = useCompaniesStore();
  companies.getRecord(7).customAttributes = { size: 'Enterprise' };
  await wrapper.vm.$nextTick();
  expect(
    wrapper.findComponent({ name: 'CrmRelationshipResources' }).props('company')
      .customAttributes.size
  ).toBe('Enterprise');
});

it('opens company editing inside the relationship panel and exposes the native footer contract', async () => {
  wrapper = makePanel();
  await flushPromises();
  await wrapper
    .find(
      'button[aria-label="CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.EDIT_TITLE"]'
    )
    .trigger('click');
  expect(wrapper.find('[data-crm-company-form]').exists()).toBe(true);
  expect(wrapper.vm.companyAction.formId).toBe(
    wrapper.find('form').attributes('id')
  );
  expect(wrapper.vm.companyAction.disabled).toBe(true);
});
it('does not offer company mutation controls to a read-only viewer', async () => {
  wrapper = makePanel({ canManage: false });
  await flushPromises();
  expect(
    wrapper
      .find(
        'button[aria-label="CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.EDIT_TITLE"]'
      )
      .exists()
  ).toBe(false);
  expect(
    wrapper
      .find('button[aria-label="CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.CHANGE"]')
      .exists()
  ).toBe(false);
});
it('requires an explicit in-card company choice for legacy company text', async () => {
  ContactAPI.show.mockResolvedValue({
    data: {
      payload: {
        ...person,
        company_id: null,
        additional_attributes: { company_name: 'Legacy company' },
      },
    },
  });
  wrapper = makePanel();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(
      button =>
        button.text() === 'CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.LINK_TITLE'
    )
    .trigger('click');
  expect(wrapper.find('[data-crm-company-form]').exists()).toBe(true);
  expect(wrapper.vm.companyAction.disabled).toBe(true);
  expect(CompanyAPI.show).not.toHaveBeenCalled();
});

it('keeps card linking but hides shared-record editors without record management', async () => {
  wrapper = makePanel({ canManage: true, canManageRecords: false });
  await flushPromises();
  expect(wrapper.find('[data-record-read-only]').exists()).toBe(true);
  expect(
    wrapper
      .findAll('button')
      .some(button => button.text() === 'CRM_KANBAN.RELATIONSHIP.EDIT')
  ).toBe(false);
  expect(
    wrapper
      .findAll('button')
      .some(button => button.text() === 'CRM_KANBAN.RELATIONSHIP.CHANGE')
  ).toBe(true);
  expect(
    wrapper
      .findComponent({ name: 'CrmRelationshipResources' })
      .props('canManage')
  ).toBe(false);
});

it('removes the generic read-only notice while choosing a different contact link', async () => {
  wrapper = makePanel({ canManage: true, canManageRecords: false });
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'CRM_KANBAN.RELATIONSHIP.CHANGE')
    .trigger('click');
  expect(wrapper.vm.linking).toBe(true);
  expect(wrapper.find('[data-record-read-only]').exists()).toBe(false);
});
