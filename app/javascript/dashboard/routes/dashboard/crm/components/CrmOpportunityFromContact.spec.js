import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import CompanyAPI from 'dashboard/api/companies';
import CrmOpportunityFromContact from './CrmOpportunityFromContact.vue';

const route = reactive({
  params: { accountId: '1' },
  query: { new_contact_id: '42' },
});
const companies = ref(true);
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('dashboard/api/contacts', () => ({ default: { show: vi.fn() } }));
vi.mock('dashboard/api/companies', () => ({ default: { show: vi.fn() } }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: ref({ id: 1 }),
    isCloudFeatureEnabled: () => companies.value,
  }),
}));
const person = {
  id: 42,
  name: 'Mariana',
  email: 'mariana@example.com',
  company_id: 7,
};
let wrapper;
const mountContext = props =>
  mount(CrmOpportunityFromContact, {
    props: { ready: true, canManage: true, ...props },
  });
beforeEach(() => {
  vi.clearAllMocks();
  window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  route.params.accountId = '1';
  route.query = { new_contact_id: '42' };
  companies.value = true;
  ContactAPI.show.mockResolvedValue({ data: { payload: { ...person } } });
  CompanyAPI.show.mockResolvedValue({
    data: { payload: { id: 7, name: 'Empresa atual' } },
  });
});
afterEach(() => wrapper?.unmount());

it('loads the canonical contact and company before opening the native form', async () => {
  wrapper = mountContext();
  await flushPromises();
  expect(ContactAPI.show).toHaveBeenCalledWith(42);
  expect(CompanyAPI.show).toHaveBeenCalledWith(7);
  expect(wrapper.emitted('open')).toEqual([
    [{ ...person, company: { id: 7, name: 'Empresa atual' } }],
  ]);
});
it('waits for a usable pipeline and emits once despite board refreshes', async () => {
  wrapper = mountContext({ ready: false });
  await flushPromises();
  expect(wrapper.text()).toContain('NEEDS_PIPELINE');
  expect(wrapper.emitted('open')).toBeUndefined();
  await wrapper.setProps({ ready: true });
  await flushPromises();
  await wrapper.setProps({ ready: false });
  await wrapper.setProps({ ready: true });
  await flushPromises();
  expect(wrapper.emitted('open')).toHaveLength(1);
});
it.each(['0', '-1', '1.2', '1e2', '042', '42x', '', ['42', '43'], null])(
  'rejects ambiguous or invalid contact query %s before reading data',
  async value => {
    route.query.new_contact_id = value;
    wrapper = mountContext();
    await flushPromises();
    expect(ContactAPI.show).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('INVALID_LINK');
    expect(wrapper.emitted('open')).toBeUndefined();
  }
);
it('does not open a new intent mixed with an existing card', async () => {
  route.query.card_id = '99';
  wrapper = mountContext();
  await flushPromises();
  expect(ContactAPI.show).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain('INVALID_LINK');
});
it('does not read contact data or open a drawer without creation permission', async () => {
  wrapper = mountContext({ canManage: false });
  await flushPromises();
  expect(ContactAPI.show).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain('UNAVAILABLE');
});
it('does not read data when CRM is globally disabled', async () => {
  window.globalConfig.CRM_KANBAN_ENABLED = 'false';
  wrapper = mountContext();
  await flushPromises();
  expect(ContactAPI.show).not.toHaveBeenCalled();
});
it('shows a failed contact lookup and retries without silently creating an unlinked card', async () => {
  ContactAPI.show.mockRejectedValueOnce(new Error('Unavailable'));
  wrapper = mountContext();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.emitted('open')).toBeUndefined();
  await wrapper.vm.load();
  await flushPromises();
  expect(wrapper.emitted('open')).toHaveLength(1);
});
it('keeps a failed company lookup visible instead of inventing or losing the association', async () => {
  CompanyAPI.show.mockRejectedValue(new Error('Unavailable'));
  wrapper = mountContext();
  await flushPromises();
  expect(wrapper.text()).toContain('LOAD_ERROR');
  expect(wrapper.emitted('open')).toBeUndefined();
});
it('does not require Companies for an existing name-only contact', async () => {
  companies.value = false;
  ContactAPI.show.mockResolvedValue({
    data: { payload: { id: 42, name: 'Pessoa' } },
  });
  wrapper = mountContext();
  await flushPromises();
  expect(CompanyAPI.show).not.toHaveBeenCalled();
  expect(wrapper.emitted('open')).toEqual([[{ id: 42, name: 'Pessoa' }]]);
});
it('drops a late contact and its follow-up company request after switching account', async () => {
  let finish;
  ContactAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  wrapper = mountContext();
  route.params.accountId = '2';
  route.query.new_contact_id = '43';
  ContactAPI.show.mockResolvedValue({
    data: { payload: { id: 43, name: 'Conta atual' } },
  });
  await wrapper.vm.load();
  await flushPromises();
  finish({ data: { payload: person } });
  await flushPromises();
  expect(CompanyAPI.show).not.toHaveBeenCalled();
  expect(
    wrapper
      .emitted('open')
      .flat()
      .every(item => item.id === 43)
  ).toBe(true);
});
it('drops a pending lookup when the intent is removed', async () => {
  let finish;
  ContactAPI.show.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  wrapper = mountContext();
  wrapper.unmount();
  finish({ data: { payload: person } });
  await flushPromises();
  expect(CompanyAPI.show).not.toHaveBeenCalled();
  expect(wrapper.emitted('open')).toBeUndefined();
});
it('cancels without emitting a creation or touching any record', async () => {
  wrapper = mountContext({ ready: false });
  await flushPromises();
  await wrapper.findAll('button').at(-1).trigger('click');
  expect(wrapper.emitted('cancel')).toHaveLength(1);
  expect(wrapper.emitted('open')).toBeUndefined();
});
