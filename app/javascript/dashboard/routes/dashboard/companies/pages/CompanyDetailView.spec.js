import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';
import CompanyDetailView from './CompanyDetailView.vue';

const testState = vi.hoisted(() => ({
  company: {
    id: 42,
    name: 'Autonom.ia',
    domain: 'autonomia.site',
    customAttributes: { cnpj: '12.345.678/0001-90' },
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '16', companyId: '42' } }),
  useRouter: () => ({ push: vi.fn(), back: vi.fn() }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/stores/companies', () => ({
  useCompaniesStore: () => ({
    getRecord: id => (Number(id) === 42 ? testState.company : {}),
    companyContacts: [],
    companyContactsMeta: { totalCount: 0, page: 1 },
    companyConversations: [],
    companyNotes: [],
    contactSearchResults: [],
    getUIFlags: {
      fetchingItem: false,
      fetchingContacts: false,
      fetchingConversations: false,
      fetchingNotes: false,
      searchingContacts: false,
      creatingContact: false,
      removingContact: false,
      deletingItem: false,
    },
    resetCompanyDetailState: vi.fn(),
    show: vi.fn().mockResolvedValue(testState.company),
    getCompanyContacts: vi.fn().mockResolvedValue([]),
    getCompanyConversations: vi.fn().mockResolvedValue([]),
    getCompanyNotes: vi.fn().mockResolvedValue([]),
    searchCompanyContactCandidates: vi.fn().mockResolvedValue([]),
    attachContactToCompany: vi.fn(),
    removeContactFromCompany: vi.fn(),
    delete: vi.fn(),
  }),
}));

const mountView = async () => {
  const wrapper = mount(CompanyDetailView, {
    global: {
      stubs: {
        CompaniesDetailsLayout: {
          template:
            '<div><slot /><slot name="sidebarHeader" /><slot name="sidebar" /></div>',
        },
        Breadcrumb: true,
        Spinner: true,
        Policy: {
          template: '<div><slot /></div>',
        },
        Button: true,
        CompanyProfileCard: true,
        ConfirmCompanyDeleteDialog: true,
        CompanyNotesSidebar: {
          template: '<div class="notes-sidebar" />',
        },
        CompanyHistorySidebar: {
          template: '<div class="history-sidebar" />',
        },
        CompanyContactsSidebar: {
          template: '<div class="contacts-sidebar" />',
        },
        CompanyCustomAttributes: {
          props: ['company'],
          template:
            '<div class="company-attributes" :data-company-id="company.id" />',
        },
        TabBar: {
          props: ['tabs'],
          emits: ['tabChanged'],
          template: `
            <div>
              <button
                v-for="tab in tabs"
                :key="tab.value"
                class="tab"
                :data-tab="tab.value"
                @click="$emit('tabChanged', tab)"
              >
                {{ tab.label }}
              </button>
            </div>
          `,
        },
      },
    },
  });

  await flushPromises();
  return wrapper;
};

describe('CompanyDetailView custom attributes', () => {
  it('keeps History as default and exposes the existing Attributes sidebar', async () => {
    const wrapper = await mountView();

    expect(wrapper.find('.history-sidebar').exists()).toBe(true);
    expect(wrapper.find('[data-tab="attributes"]').exists()).toBe(true);
    expect(wrapper.find('.company-attributes').exists()).toBe(false);

    await wrapper.find('[data-tab="attributes"]').trigger('click');
    await nextTick();

    expect(wrapper.find('.history-sidebar').exists()).toBe(false);
    expect(wrapper.find('.company-attributes').exists()).toBe(true);
    expect(
      wrapper.find('.company-attributes').attributes('data-company-id')
    ).toBe('42');
  });
});
