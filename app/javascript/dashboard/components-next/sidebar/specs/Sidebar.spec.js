import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import Sidebar from '../Sidebar.vue';

// Onde o Agendamento aparece no menu (#1212, #1264): subgrupo do CRM, entre
// Calendário e Dashboard, com Páginas e links, Meus horários e Meus números;
// fora de Configurações.
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

const seat = ({
  role = 'administrator',
  customRoleId = null,
  keys = [],
  bookingV2 = true,
}) => {
  Object.assign(getters, {
    'globalConfig/get': ref({ crmKanbanEnabled: true }),
    getCurrentAccountId: ref(9),
    getCurrentRole: ref(role),
    getCurrentCustomRoleId: ref(customRoleId),
    getCurrentUser: ref({ accounts: [{ id: 9, permissions: keys }] }),
    'accounts/getAccount': ref(() => ({
      id: 9,
      features: { crm_booking_v2: bookingV2 },
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

const schedulingOf = wrapper =>
  wrapper
    .findAllComponents({ name: 'SidebarGroup' })
    .find(item => item.props('name') === 'CRM')
    ?.props('children')
    .find(child => child.name === 'CRM Scheduling');

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

  it('administrador vê o subgrupo entre Calendário e Dashboard, com os 3 filhos', () => {
    seat({});
    const wrapper = mountSidebar();
    const crm = childrenOf(wrapper, 'CRM');
    const calendar = crm.indexOf('CRM Calendar');
    expect(crm.slice(calendar, calendar + 3)).toEqual([
      'CRM Calendar',
      'CRM Scheduling',
      'CRM Dashboard',
    ]);
    expect(crm).not.toContain('CRM Booking');

    const scheduling = schedulingOf(wrapper);
    expect(scheduling.label).toBe('SIDEBAR.BOOKING');
    expect(scheduling.icon).toBe('i-lucide-calendar-clock');
    expect(scheduling.children.map(child => child.name)).toEqual([
      'CRM Booking',
      'CRM My Booking Hours',
      'CRM Booking Results',
    ]);
    expect(scheduling.children[0]).toMatchObject({
      label: 'BOOKING.PAGE.MENU',
      to: { name: 'settings_booking' },
      activeOn: ['settings_booking', 'settings_booking_results'],
    });
  });

  it('saiu do grupo Configurações', () => {
    seat({});
    const settings = childrenOf(mountSidebar(), 'Settings');
    expect(settings).toContain('Settings Account Settings');
    expect(settings).not.toContain('CRM Booking');
    expect(settings).not.toContain('Settings Booking');
  });

  it('função só com Agendamento, sem CRM, vê o CRM só com o subgrupo e sem Kanban', () => {
    seat({ role: 'agent', customRoleId: 7, keys: ['agendamento_view'] });
    const wrapper = mountSidebar();
    expect(childrenOf(wrapper, 'CRM')).toEqual(['CRM Scheduling']);
    expect(schedulingOf(wrapper).children.map(child => child.name)).toEqual([
      'CRM Booking',
    ]);
  });

  it('flag desligada: nenhum item de Agendamento, e a função só com ele perde o CRM', () => {
    seat({ bookingV2: false });
    const crm = childrenOf(mountSidebar(), 'CRM');
    expect(crm).toContain('CRM Kanban');
    expect(crm).not.toContain('CRM Scheduling');

    seat({
      role: 'agent',
      customRoleId: 7,
      keys: ['agendamento_view'],
      bookingV2: false,
    });
    expect(childrenOf(mountSidebar(), 'CRM')).toBeUndefined();
  });

  it('função sem CRM e sem Agendamento continua sem o grupo CRM', () => {
    seat({ role: 'agent', customRoleId: 7, keys: ['label_manage'] });
    expect(childrenOf(mountSidebar(), 'CRM')).toBeUndefined();
  });
});
