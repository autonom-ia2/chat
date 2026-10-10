import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import Sidebar from '../Sidebar.vue';

// Onde o Agendamento aparece no menu (#1212): no grupo CRM, logo abaixo do
// Calendário e antes de Meus horários e Meus números; fora de Configurações.
const getters = {};

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ fullPath: '/', params: {} }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => getters[key] || ref(() => 0),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
    isOnChatwootCloud: ref(false),
  }),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false }),
}));
vi.mock('dashboard/composables/utils/useKbd', () => ({
  useKbd: () => ref(''),
}));
vi.mock('dashboard/composables/useBrandedSidebar', () => ({
  useBrandedSidebar: () => ({ brandedColor: ref('') }),
}));
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({ navigationEnabled: ref(false) }),
}));
vi.mock('dashboard/composables/useScrollActiveItemIntoView', () => ({
  useScrollActiveItemIntoView: vi.fn(),
}));
vi.mock('../provider', async () => {
  const { ref: flag } = await import('vue');
  return {
    provideSidebarContext: vi.fn(),
    useSidebarResize: () => ({
      sidebarWidth: flag(200),
      isCollapsed: flag(false),
      setSidebarWidth: vi.fn(),
      saveWidth: vi.fn(),
      snapToCollapsed: vi.fn(),
      snapToExpanded: vi.fn(),
    }),
  };
});
vi.mock('../useSidebarKeyboardShortcuts', () => ({
  useSidebarKeyboardShortcuts: vi.fn(),
}));

const seat = ({ role = 'administrator', customRoleId = null, keys = [] }) => {
  Object.assign(getters, {
    'globalConfig/get': ref({ crmKanbanEnabled: true }),
    getCurrentAccountId: ref(9),
    getCurrentRole: ref(role),
    getCurrentCustomRoleId: ref(customRoleId),
    getCurrentUser: ref({ accounts: [{ id: 9, permissions: keys }] }),
    'accounts/getAccount': ref(() => ({
      id: 9,
      features: { crm_booking_v2: true },
    })),
    'accounts/isFeatureEnabledonAccount': ref(() => false),
    'inboxes/getInboxes': ref([]),
    'labels/getLabelsOnSidebar': ref([]),
    'teams/getMyTeams': ref([]),
    'customViews/getContactCustomViews': ref([]),
    'customViews/getConversationCustomViews': ref([]),
  });
};

const childrenOf = (wrapper, group) =>
  wrapper
    .findAllComponents({ name: 'SidebarGroup' })
    .find(item => item.props('name') === group)
    ?.props('children')
    .map(child => child.name);

const mountSidebar = () =>
  shallowMount(Sidebar, {
    global: {
      stubs: {
        RouterLink: true,
        SidebarGroup: {
          name: 'SidebarGroup',
          props: ['name', 'children'],
          template: '<li />',
        },
      },
    },
  });

describe('Sidebar: Agendamento no grupo CRM', () => {
  beforeEach(() => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
  });

  afterEach(() => {
    delete window.globalConfig;
  });

  it('fica logo abaixo do Calendário, antes de Meus horários e Meus números', () => {
    seat({});
    const crm = childrenOf(mountSidebar(), 'CRM');
    const calendar = crm.indexOf('CRM Calendar');
    expect(crm.slice(calendar, calendar + 4)).toEqual([
      'CRM Calendar',
      'CRM Booking',
      'CRM My Booking Hours',
      'CRM Booking Results',
    ]);
  });

  it('saiu do grupo Configurações', () => {
    seat({});
    const settings = childrenOf(mountSidebar(), 'Settings');
    expect(settings).toContain('Settings Account Settings');
    expect(settings).not.toContain('CRM Booking');
    expect(settings).not.toContain('Settings Booking');
  });

  it('função só com Agendamento, sem CRM, ainda recebe o grupo CRM com o item', () => {
    seat({ role: 'agent', customRoleId: 7, keys: ['agendamento_view'] });
    expect(childrenOf(mountSidebar(), 'CRM')).toContain('CRM Booking');
  });

  it('função sem CRM e sem Agendamento continua sem o grupo CRM', () => {
    seat({ role: 'agent', customRoleId: 7, keys: ['label_manage'] });
    expect(childrenOf(mountSidebar(), 'CRM')).toBeUndefined();
  });
});
