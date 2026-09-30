import { mount, flushPromises } from '@vue/test-utils';
import CompanyAPI from 'dashboard/api/companies';
import CrmOpportunityCompanyPicker from './CrmOpportunityCompanyPicker.vue';
vi.mock('dashboard/api/companies', () => ({ default: { search: vi.fn() } }));
let wrapper;
beforeEach(() => vi.clearAllMocks());
afterEach(() => wrapper?.unmount());
it('does not load the company base when opening the picker', () => {
  wrapper = mount(CrmOpportunityCompanyPicker);
  expect(CompanyAPI.search).not.toHaveBeenCalled();
});
it('uses account API pagination and emits only a user-selected real company', async () => {
  const company = { id: 7, name: 'Existing', domain: 'existing.example' };
  CompanyAPI.search.mockResolvedValue({
    data: { payload: [company], meta: { total_count: 30 } },
  });
  wrapper = mount(CrmOpportunityCompanyPicker);
  wrapper.vm.query = 'Existing';
  await wrapper.vm.search(2);
  expect(CompanyAPI.search).toHaveBeenCalledWith('Existing', 2, 'name');
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  await wrapper.find('[data-registration-company-result]').trigger('click');
  expect(wrapper.emitted('update:modelValue')[0][0]).toEqual(company);
});
it('drops a late page from the old search instead of showing a wrong company', async () => {
  let finish;
  CompanyAPI.search.mockReturnValue(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  wrapper = mount(CrmOpportunityCompanyPicker);
  wrapper.vm.query = 'Old';
  const pending = wrapper.vm.search();
  wrapper.vm.query = 'New';
  finish({
    data: { payload: [{ id: 7, name: 'Old' }], meta: { total_count: 1 } },
  });
  await pending;
  await flushPromises();
  expect(wrapper.vm.results).toEqual([]);
});
it('keeps search errors visible and allows retry without creating anything', async () => {
  CompanyAPI.search
    .mockRejectedValueOnce(new Error('Offline'))
    .mockResolvedValue({ data: { payload: [], meta: { total_count: 0 } } });
  wrapper = mount(CrmOpportunityCompanyPicker);
  wrapper.vm.query = 'Company';
  await wrapper.vm.search();
  expect(wrapper.vm.failed).toBe(true);
  await wrapper.vm.search();
  expect(wrapper.vm.failed).toBe(false);
  expect(wrapper.vm.searched).toBe(true);
});
it('cannot clear the selected company while the enclosing registration is saving', async () => {
  wrapper = mount(CrmOpportunityCompanyPicker, {
    props: { modelValue: { id: 7, name: 'Existing' }, disabled: true },
  });
  expect(wrapper.find('button').attributes()).toHaveProperty('disabled');
  await wrapper.find('button').trigger('click');
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
});
