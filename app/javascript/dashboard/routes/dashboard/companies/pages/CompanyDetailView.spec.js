import { mount, flushPromises } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import CompanyDetailView from './CompanyDetailView.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

vi.mock('dashboard/api/crmKanban', () => ({
  default: { getCompanyOpportunities: vi.fn() },
}));
const testState = vi.hoisted(() => ({
  flags: null,
  navigation: null,
  canViewCrm: null,
  recordWrite: null,
  query: {},
  company: {
    id: 42,
    name: 'Autonom.ia',
    domain: 'autonomia.site',
    customAttributes: { cnpj: '12.345.678/0001-90' },
  },
}));

vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canViewCrm: testState.canViewCrm }),
}));

vi.mock('dashboard/composables/useRelationshipPermissions', () => ({
  useRelationshipPermissions: () => ({
    canManageRelationshipRecords: testState.recordWrite,
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(16),
    currentAccount: ref({ id: 16 }),
    isCloudFeatureEnabled: name =>
      name === 'relationships_navigation'
        ? testState.navigation.value
        : ['companies', 'relationships_company_media'].includes(name) &&
          testState.flags.value,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    commit: vi.fn(),
    subscribe: vi.fn(),
    getters: { getCurrentUserID: 1 },
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: '16', companyId: '42' },
    query: testState.query,
  }),
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
        RouterLink: true,
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
        RelationshipOpportunities: {
          props: ['list', 'entity'],
          template:
            '<div data-company-opportunity-view :data-entity="entity" />',
        },
        CompanyMedia: { template: '<div class="company-media" />' },
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

beforeEach(() => {
  testState.flags = ref(false);
  testState.navigation = ref(false);
  testState.canViewCrm = ref(true);
  testState.recordWrite = ref(true);
  window.globalConfig = { ...window.globalConfig, CRM_KANBAN_ENABLED: 'true' };
  CrmKanbanAPI.getCompanyOpportunities.mockReset();
  CrmKanbanAPI.getCompanyOpportunities.mockResolvedValue({
    data: { payload: [], meta: { total_count: 0, page: 1, has_more: false } },
  });
  testState.query = {};
});

it('keeps Contacts as the entry and only reads opportunities after opening the authorized tab', async () => {
  testState.flags.value = true;
  testState.navigation.value = true;
  const wrapper = await mountView();
  expect(wrapper.find('.contacts-sidebar').exists()).toBe(true);
  expect(CrmKanbanAPI.getCompanyOpportunities).not.toHaveBeenCalled();
  wrapper.vm.handleSidebarTabChange({ value: 'opportunities' });
  await flushPromises();
  expect(CrmKanbanAPI.getCompanyOpportunities).toHaveBeenCalledOnce();
  expect(CrmKanbanAPI.getCompanyOpportunities.mock.lastCall[0]).toBe(42);
  expect(
    wrapper.find('[data-company-opportunity-view]').attributes('data-entity')
  ).toBe('company');
  wrapper.unmount();
});

it.each(['permission', 'companies', 'navigation'])(
  'hides opportunities when %s is unavailable without removing other tabs',
  async gate => {
    testState.flags.value = gate !== 'companies';
    testState.navigation.value = gate !== 'navigation';
    testState.canViewCrm.value = gate !== 'permission';
    const wrapper = await mountView();
    expect(wrapper.vm.sidebarTabs.map(tab => tab.value)).not.toContain(
      'opportunities'
    );
    expect(wrapper.vm.sidebarTabs.map(tab => tab.value)).toEqual(
      expect.arrayContaining(['contacts', 'notes', 'history', 'attributes'])
    );
    expect(CrmKanbanAPI.getCompanyOpportunities).not.toHaveBeenCalled();
    wrapper.unmount();
  }
);

it('removes active opportunities and their totals when viewing permission is revoked', async () => {
  testState.flags.value = true;
  testState.navigation.value = true;
  const wrapper = await mountView();
  wrapper.vm.handleSidebarTabChange({ value: 'opportunities' });
  await flushPromises();
  testState.canViewCrm.value = false;
  await nextTick();
  expect(wrapper.find('[data-company-opportunity-view]').exists()).toBe(false);
  expect(wrapper.find('.contacts-sidebar').exists()).toBe(true);
  expect(wrapper.vm.opportunityList.state.total).toBe(0);
  wrapper.unmount();
});

describe('CompanyDetailView custom attributes', () => {
  it('opens Contacts by default and exposes the existing Attributes sidebar', async () => {
    const wrapper = await mountView();

    expect(wrapper.find('.contacts-sidebar').exists()).toBe(true);
    expect(wrapper.find('[data-tab="attributes"]').exists()).toBe(true);
    expect(wrapper.find('.company-attributes').exists()).toBe(false);

    await wrapper.find('[data-tab="attributes"]').trigger('click');
    await nextTick();

    expect(wrapper.find('.contacts-sidebar').exists()).toBe(false);
    expect(wrapper.find('.company-attributes').exists()).toBe(true);
    expect(
      wrapper.find('.company-attributes').attributes('data-company-id')
    ).toBe('42');
  });
});

it('restores Media from the detail return query and exits Media when flags turn off', async () => {
  testState.flags.value = true;
  testState.query = {
    media: JSON.stringify({ q: 'proposal', contact_id: '4', page: 2 }),
  };
  const wrapper = await mountView();
  expect(wrapper.find('.company-media').exists()).toBe(true);
  expect(wrapper.find('.contacts-sidebar').exists()).toBe(false);
  expect(JSON.parse(testState.query.media)).toEqual({
    q: 'proposal',
    contact_id: '4',
    page: 2,
  });
  testState.flags.value = false;
  await nextTick();
  expect(wrapper.find('.company-media').exists()).toBe(false);
  expect(wrapper.find('.contacts-sidebar').exists()).toBe(true);
  wrapper.unmount();
});
it('ignores media query when media flags are off', async () => {
  testState.query = { media: '{}' };
  const wrapper = await mountView();
  expect(wrapper.find('.company-media').exists()).toBe(false);
  expect(wrapper.find('.contacts-sidebar').exists()).toBe(true);
  wrapper.unmount();
});

it('restores the media return context when the account flags finish loading', async () => {
  testState.query = { media: JSON.stringify({ q: 'proposal', page: 2 }) };
  const wrapper = await mountView();
  expect(wrapper.find('.contacts-sidebar').exists()).toBe(true);
  testState.flags.value = true;
  await nextTick();
  expect(wrapper.find('.company-media').exists()).toBe(true);
  expect(wrapper.find('.contacts-sidebar').exists()).toBe(false);
  wrapper.unmount();
});
