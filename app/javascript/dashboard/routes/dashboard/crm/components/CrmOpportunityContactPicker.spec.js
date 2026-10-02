import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import CrmOpportunityContactPicker from './CrmOpportunityContactPicker.vue';

const accountId = ref(1);
const enabled = ref(true);
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId,
    currentAccount: ref({ id: 1 }),
    isCloudFeatureEnabled: () => enabled.value,
  }),
}));
const person = {
  id: 42,
  name: 'Mariana',
  email: 'mariana@example.com',
  company_id: 7,
  company: { id: 7, name: 'Empresa atual' },
};
const makePicker = props =>
  mount(CrmOpportunityContactPicker, {
    props,
    global: { stubs: { Avatar: true } },
  });
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  accountId.value = 1;
  enabled.value = true;
  ContactAPI.search.mockResolvedValue({
    data: { payload: [person], meta: { has_more: false } },
  });
});
afterEach(() => wrapper?.unmount());
it('does not load all contacts on mount or on a one-character query', async () => {
  wrapper = makePicker();
  await wrapper.find('input').setValue('M');
  await wrapper.vm.search();
  expect(ContactAPI.search).not.toHaveBeenCalled();
});
it('searches the real account with explicit company support and a cancellation signal', async () => {
  wrapper = makePicker();
  await wrapper.find('input').setValue('Empresa atual');
  await wrapper.vm.search();
  expect(ContactAPI.search).toHaveBeenCalledWith(
    'Empresa atual',
    1,
    'name',
    '',
    {
      includeCompany: true,
      signal: expect.any(AbortSignal),
    }
  );
  expect(wrapper.text()).toContain('Mariana');
  expect(wrapper.text()).toContain('Empresa atual');
});
it('selects an ID-bearing record without writing a contact or opportunity', async () => {
  wrapper = makePicker();
  await wrapper.find('input').setValue('Mariana');
  await wrapper.vm.search();
  await wrapper.find('[data-opportunity-contact-result]').trigger('click');
  expect(wrapper.emitted('update:modelValue')).toEqual([[person]]);
});
it('shows canonical company details, never inferring the association from legacy text', () => {
  wrapper = makePicker({
    modelValue: {
      ...person,
      company_id: null,
      company: null,
      additional_attributes: { company_name: 'Nome legado' },
    },
  });
  expect(wrapper.text()).toContain('NO_COMPANY');
  expect(wrapper.text()).not.toContain('Nome legado');
});
it('keeps email and phone visible in the selected record', () => {
  wrapper = makePicker({
    modelValue: { ...person, phone_number: '+5531900000001' },
  });
  expect(wrapper.text()).toContain('mariana@example.com');
  expect(wrapper.text()).toContain('+5531900000001');
  expect(wrapper.text()).toContain('Empresa atual');
});
it('supports explicit selection clearing', async () => {
  wrapper = makePicker({ modelValue: person });
  await wrapper.find('button').trigger('click');
  expect(wrapper.emitted('update:modelValue')).toEqual([[null]]);
});
it('clears obsolete results as soon as the query changes', async () => {
  wrapper = makePicker();
  await wrapper.find('input').setValue('Mariana');
  await wrapper.vm.search();
  await wrapper.find('input').setValue('João');
  expect(wrapper.findAll('[data-opportunity-contact-result]')).toHaveLength(0);
});
it('ignores a late response after typing another query', async () => {
  let finish;
  ContactAPI.search.mockReturnValue(
    new Promise(done => {
      finish = done;
    })
  );
  wrapper = makePicker();
  await wrapper.find('input').setValue('Primeiro');
  const pending = wrapper.vm.search();
  await wrapper.find('input').setValue('Segundo');
  finish({ data: { payload: [person], meta: {} } });
  await pending;
  expect(wrapper.findAll('[data-opportunity-contact-result]')).toHaveLength(0);
});
it('cancels the old account request and clears the selected record on an account change', async () => {
  let finish;
  ContactAPI.search.mockReturnValue(
    new Promise(done => {
      finish = done;
    })
  );
  wrapper = makePicker();
  await wrapper.find('input').setValue('Mariana');
  const pending = wrapper.vm.search();
  accountId.value = 2;
  finish({ data: { payload: [person], meta: {} } });
  await pending;
  expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([null]);
  expect(wrapper.findAll('[data-opportunity-contact-result]')).toHaveLength(0);
});
it('shows a failed lookup as an error, not an empty successful result', async () => {
  ContactAPI.search.mockRejectedValue(new Error('Offline'));
  wrapper = makePicker();
  await wrapper.find('input').setValue('Mariana');
  await wrapper.vm.search();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.text()).not.toContain('NO_RESULTS');
});
it('paginates using the server has_more result instead of limiting a local contact list', async () => {
  ContactAPI.search.mockResolvedValue({
    data: { payload: [person], meta: { has_more: true } },
  });
  wrapper = makePicker();
  await wrapper.find('input').setValue('Contato');
  await wrapper.vm.search();
  await wrapper.vm.search(2);
  expect(ContactAPI.search.mock.lastCall[1]).toBe(2);
  expect(wrapper.vm.page).toBe(2);
});
it('uses the standard lookup and hides company state when Companies is disabled', async () => {
  enabled.value = false;
  wrapper = makePicker();
  await wrapper.find('input').setValue('Mariana');
  await wrapper.vm.search();
  expect(ContactAPI.search.mock.lastCall[4].includeCompany).toBe(false);
  await wrapper.setProps({ modelValue: person });
  expect(wrapper.text()).not.toContain('Empresa atual');
});
it('does not allow search or selection during a save', async () => {
  wrapper = makePicker({ disabled: true });
  wrapper.vm.query = 'Mariana';
  await wrapper.vm.search();
  wrapper.vm.select(person);
  expect(ContactAPI.search).not.toHaveBeenCalled();
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
});
it('drops results after the picker is unmounted', async () => {
  let finish;
  ContactAPI.search.mockReturnValue(
    new Promise(done => {
      finish = done;
    })
  );
  wrapper = makePicker();
  await wrapper.find('input').setValue('Mariana');
  const pending = wrapper.vm.search();
  wrapper.unmount();
  finish({ data: { payload: [person], meta: {} } });
  await pending;
  await flushPromises();
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
});
