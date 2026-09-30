import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import CompanyAPI from 'dashboard/api/companies';
import ContactAPI from 'dashboard/api/contacts';
import CrmRelationshipCompanyForm from './CrmRelationshipCompanyForm.vue';

const context = vi.hoisted(() => ({ update: vi.fn() }));
const accountId = ref(1);
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId }),
}));
vi.mock('dashboard/stores/companies', () => ({
  useCompaniesStore: () => context,
}));
vi.mock('dashboard/api/companies', () => ({ default: { search: vi.fn() } }));
vi.mock('dashboard/api/contacts', () => ({ default: { update: vi.fn() } }));
const company = {
  id: 7,
  name: 'Horizonte',
  domain: 'horizonte.example',
  description: 'Original',
  customAttributes: { keep: 1 },
};
const contact = { id: 42, name: 'Mariana', company_id: 7 };
const makeForm = (props = {}) =>
  mount(CrmRelationshipCompanyForm, {
    props: { company, contact, mode: 'edit', formId: 'company-test', ...props },
  });
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  accountId.value = 1;
  context.update.mockResolvedValue(company);
  CompanyAPI.search.mockResolvedValue({
    data: {
      payload: [{ id: 8, name: 'Alameda', domain: 'alameda.example' }],
      meta: { total_count: 1 },
    },
  });
  ContactAPI.update.mockResolvedValue({
    data: { payload: { id: 42, company_id: 8 } },
  });
});
afterEach(() => wrapper?.unmount());

it('does not create or update anything on opening an edit form', () => {
  wrapper = makeForm();
  expect(wrapper.vm.canSave).toBe(false);
  expect(wrapper.vm.dirty).toBe(false);
  expect(context.update).not.toHaveBeenCalled();
  expect(ContactAPI.update).not.toHaveBeenCalled();
});
it('saves only edited company fields, not old custom attributes or opportunity data', async () => {
  wrapper = makeForm();
  await wrapper.find('input').setValue('Horizonte Seguros');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(context.update).toHaveBeenCalledExactlyOnceWith({
    id: 7,
    name: 'Horizonte Seguros',
  });
  expect(ContactAPI.update).not.toHaveBeenCalled();
  expect(wrapper.emitted('saved')).toEqual([['edit']]);
});
it('clears an optional domain with null and preserves an untouched description', async () => {
  wrapper = makeForm();
  await wrapper.findAll('input')[1].setValue('  ');
  await wrapper.find('form').trigger('submit');
  expect(context.update).toHaveBeenCalledWith({ id: 7, domain: null });
});
it('keeps the local draft when the shared record changes while typing', async () => {
  wrapper = makeForm();
  await wrapper.find('input').setValue('My draft');
  await wrapper.setProps({
    company: {
      ...company,
      name: 'Realtime name',
      description: 'Realtime description',
    },
  });
  expect(wrapper.find('input').element.value).toBe('My draft');
  await wrapper.find('form').trigger('submit');
  expect(context.update).toHaveBeenCalledWith({ id: 7, name: 'My draft' });
});
it('does not save a blank name', async () => {
  wrapper = makeForm();
  await wrapper.find('input').setValue('   ');
  await wrapper.find('form').trigger('submit');
  expect(context.update).not.toHaveBeenCalled();
});
it('keeps the input and announces failure rather than success after a rejected update', async () => {
  context.update.mockRejectedValue(new Error('Duplicate domain'));
  wrapper = makeForm();
  await wrapper.findAll('input')[1].setValue('duplicate.example');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.findAll('input')[1].element.value).toBe('duplicate.example');
  expect(wrapper.find('[role=alert]').text()).toContain('EDIT_ERROR');
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.vm.dirty).toBe(true);
});
it('prevents duplicate submissions while a write is pending', async () => {
  let resolve;
  context.update.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  wrapper = makeForm();
  await wrapper.find('input').setValue('Updated');
  await wrapper.find('form').trigger('submit');
  await wrapper.find('form').trigger('submit');
  expect(context.update).toHaveBeenCalledTimes(1);
  expect(wrapper.vm.saving).toBe(true);
  resolve(company);
  await flushPromises();
  expect(wrapper.vm.saving).toBe(false);
});
it.each(['edit', 'link', 'unlink'])(
  'does not mutate in read-only %s mode',
  async mode => {
    wrapper = makeForm({ mode, readOnly: true });
    wrapper.vm.form.name = 'Updated';
    wrapper.vm.selected = { id: 8 };
    await wrapper.find('form').trigger('submit');
    expect(context.update).not.toHaveBeenCalled();
    expect(ContactAPI.update).not.toHaveBeenCalled();
  }
);
it('shows company domains to distinguish identical names and requires explicit save', async () => {
  CompanyAPI.search.mockResolvedValue({
    data: {
      payload: [
        { id: 8, name: 'Same name', domain: 'first.example' },
        { id: 9, name: 'Same name', domain: 'second.example' },
      ],
      meta: { total_count: 2 },
    },
  });
  wrapper = makeForm({ mode: 'link' });
  await wrapper.find('input[type=search]').setValue('Same');
  await wrapper.vm.search();
  await flushPromises();
  const options = wrapper.findAll('button[aria-pressed]');
  expect(options).toHaveLength(2);
  expect(options[1].text()).toContain('second.example');
  await options[1].trigger('click');
  expect(ContactAPI.update).not.toHaveBeenCalled();
  ContactAPI.update.mockResolvedValue({
    data: { payload: { id: 42, company_id: 9 } },
  });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(ContactAPI.update).toHaveBeenCalledExactlyOnceWith(42, {
    company_id: 9,
  });
  expect(wrapper.emitted('saved')).toEqual([['link']]);
});
it('does not allow reselecting the already linked company', async () => {
  CompanyAPI.search.mockResolvedValue({
    data: { payload: [company], meta: { total_count: 1 } },
  });
  wrapper = makeForm({ mode: 'link' });
  await wrapper.find('input[type=search]').setValue('Horizonte');
  await wrapper.vm.search();
  await flushPromises();
  expect(
    wrapper.find('button[aria-pressed]').attributes('disabled')
  ).toBeDefined();
});
it('uses server pagination and retains the selected company', async () => {
  CompanyAPI.search.mockResolvedValue({
    data: {
      payload: [{ id: 8, name: 'Alameda', domain: '' }],
      meta: { total_count: 30 },
    },
  });
  wrapper = makeForm({ mode: 'link' });
  await wrapper.find('input[type=search]').setValue('Alameda');
  await wrapper.vm.search();
  await flushPromises();
  await wrapper.find('button[aria-pressed]').trigger('click');
  await wrapper.vm.search(2);
  expect(CompanyAPI.search).toHaveBeenLastCalledWith('Alameda', 2, 'name');
  expect(wrapper.vm.selected.id).toBe(8);
});
it('invalidates a selected company when the search text changes', async () => {
  wrapper = makeForm({ mode: 'link' });
  await wrapper.find('input[type=search]').setValue('Alameda');
  await wrapper.vm.search();
  await flushPromises();
  await wrapper.find('button[aria-pressed]').trigger('click');
  await wrapper.find('input[type=search]').setValue('Other');
  expect(wrapper.vm.selected).toBe(null);
  expect(wrapper.vm.canSave).toBe(false);
});
it('ignores a late search response after the query changes', async () => {
  let resolve;
  CompanyAPI.search.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  wrapper = makeForm({ mode: 'link' });
  await wrapper.find('input[type=search]').setValue('First');
  const previous = wrapper.vm.search();
  await wrapper.find('input[type=search]').setValue('Second');
  resolve({
    data: {
      payload: [{ id: 99, name: 'Old result' }],
      meta: { total_count: 1 },
    },
  });
  await previous;
  await flushPromises();
  expect(wrapper.text()).not.toContain('Old result');
});
it('searches on Enter without linking any company', async () => {
  wrapper = makeForm({ mode: 'link' });
  await wrapper.find('input[type=search]').setValue('Alameda');
  await wrapper.find('input[type=search]').trigger('keydown', { key: 'Enter' });
  await flushPromises();
  expect(CompanyAPI.search).toHaveBeenCalledWith('Alameda', 1, 'name');
  expect(ContactAPI.update).not.toHaveBeenCalled();
});
it('removes only the association after explicit confirmation', async () => {
  ContactAPI.update.mockResolvedValue({
    data: { payload: { id: 42, company_id: null } },
  });
  wrapper = makeForm({ mode: 'unlink' });
  expect(wrapper.find('[data-company-unlink-confirmation]').exists()).toBe(
    true
  );
  expect(ContactAPI.update).not.toHaveBeenCalled();
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(ContactAPI.update).toHaveBeenCalledExactlyOnceWith(42, {
    company_id: null,
  });
  expect(context.update).not.toHaveBeenCalled();
  expect(wrapper.emitted('saved')).toEqual([['unlink']]);
});
it('does not report success when the server did not change the association', async () => {
  wrapper = makeForm({ mode: 'unlink' });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.find('[role=alert]').text()).toContain('NOT_CONFIRMED');
});
it.each(['unmount', 'account'])(
  'does not emit an old save after %s',
  async change => {
    let resolve;
    ContactAPI.update.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    wrapper = makeForm({ mode: 'unlink' });
    await wrapper.find('form').trigger('submit');
    if (change === 'unmount') wrapper.unmount();
    else accountId.value = 2;
    resolve({ data: { payload: { id: 42, company_id: null } } });
    await flushPromises();
    expect(wrapper.emitted('saved')).toBeUndefined();
  }
);

it('blocks an observed company-link change without overwriting another company or discarding the draft', async () => {
  wrapper = makeForm();
  await wrapper.find('input').setValue('Keep this draft');
  await wrapper.setProps({
    contact: { ...contact, company_id: 8 },
    company: null,
  });
  expect(wrapper.find('input').element.value).toBe('Keep this draft');
  expect(wrapper.find('[role=alert]').text()).toContain('STALE');
  await wrapper.find('form').trigger('submit');
  expect(context.update).not.toHaveBeenCalled();
  expect(ContactAPI.update).not.toHaveBeenCalled();
});
it('distinguishes a failed search from an empty result without creating a company', async () => {
  CompanyAPI.search.mockRejectedValue(new Error('offline'));
  wrapper = makeForm({ mode: 'link' });
  await wrapper.find('input[type=search]').setValue('Missing');
  await wrapper.vm.search();
  expect(wrapper.find('[role=alert]').text()).toContain('SEARCH_ERROR');
  expect(wrapper.vm.canSave).toBe(false);
  expect(context.update).not.toHaveBeenCalled();
});

it('does not mistake an omitted company_id for a confirmed unlink when Companies was disabled', async () => {
  ContactAPI.update.mockResolvedValue({ data: { payload: { id: 42 } } });
  wrapper = makeForm({ mode: 'unlink' });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.find('[role=alert]').text()).toContain('NOT_CONFIRMED');
});
