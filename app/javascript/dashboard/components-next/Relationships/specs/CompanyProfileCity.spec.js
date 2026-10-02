import { mount } from '@vue/test-utils';
import CompanyProfileCard from 'dashboard/components-next/Companies/CompanyDetail/CompanyProfileCard.vue';

const companyStore = { getUIFlags: {}, update: vi.fn() };
vi.mock('dashboard/stores/companies', () => ({
  useCompaniesStore: () => companyStore,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const make = () =>
  mount(CompanyProfileCard, {
    props: {
      company: {
        id: 7,
        name: 'Company',
        domain: 'company.example',
        description: 'Original',
        additionalAttributes: { city: 'Original city' },
      },
    },
    global: { stubs: { Avatar: true }, directives: { tooltip: {} } },
  });
beforeEach(() => vi.clearAllMocks());
it('reads the canonical company city and submits only its changed detail', async () => {
  const wrapper = make();
  expect(wrapper.vm.form.city).toBe('Original city');
  expect(wrapper.vm.hasChanges).toBe(false);
  wrapper.vm.form.city = 'New city';
  companyStore.update.mockResolvedValue({
    id: 7,
    name: 'Company',
    domain: 'company.example',
    description: 'Original',
    additionalAttributes: { city: 'New city' },
  });
  await wrapper.vm.handleUpdateCompany();
  expect(companyStore.update).toHaveBeenCalledWith({
    id: 7,
    name: 'Company',
    domain: 'company.example',
    description: 'Original',
    additionalAttributes: { city: 'New city' },
  });
  wrapper.unmount();
});
it('does not include a stale city when only the company name changes', async () => {
  const wrapper = make();
  wrapper.vm.form.name = 'Updated name';
  companyStore.update.mockResolvedValue({
    id: 7,
    name: 'Updated name',
    additionalAttributes: { city: 'Server city' },
  });
  await wrapper.vm.handleUpdateCompany();
  expect(companyStore.update.mock.lastCall[0]).not.toHaveProperty(
    'additionalAttributes'
  );
  expect(wrapper.vm.form.city).toBe('Server city');
  wrapper.unmount();
});
it('clears an explicitly removed city using null without a whole-object replacement', async () => {
  const wrapper = make();
  wrapper.vm.form.city = '';
  companyStore.update.mockResolvedValue({
    id: 7,
    name: 'Company',
    additionalAttributes: { city: null },
  });
  await wrapper.vm.handleUpdateCompany();
  expect(companyStore.update.mock.lastCall[0].additionalAttributes).toEqual({
    city: null,
  });
  wrapper.unmount();
});
