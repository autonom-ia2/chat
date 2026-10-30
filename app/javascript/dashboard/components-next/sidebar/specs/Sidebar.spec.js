import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import Sidebar from '../Sidebar.vue';

// Onde o Agendamento aparece no menu (#1212, #1264, #1288): subgrupo do CRM,
// entre Kanban e Dashboard, recolhível e fechado por padrão, com Calendário,
// Páginas e links, Meus horários e Meus números; fora de Configurações. Sem a
// flag do agendamento novo, o Calendário continua solto no CRM.
const getters = {};

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ fullPath: '/', params: {} }),
  // #2211: o Sidebar instala o ⌘K da busca da lista (useAtalhoDaBusca).
  useRouter: () => ({ push: vi.fn() }),
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

  it('administrador vê o subgrupo entre Kanban e Dashboard, com os 4 filhos e o Calendário primeiro', () => {
    seat({});
    const wrapper = mountSidebar();
    const crm = childrenOf(wrapper, 'CRM');
    expect(crm.slice(0, 3)).toEqual([
      'CRM Kanban',
      'CRM Scheduling',
      'CRM Dashboard',
    ]);
    expect(crm).not.toContain('CRM Calendar');
    expect(crm).not.toContain('CRM Booking');

    const scheduling = schedulingOf(wrapper);
    expect(scheduling.label).toBe('SIDEBAR.BOOKING');
    expect(scheduling.icon).toBe('i-lucide-calendar-clock');
    expect(scheduling.children.map(child => child.name)).toEqual([
      'CRM Calendar',
      'CRM Booking',
      'CRM My Booking Hours',
      'CRM Booking Results',
    ]);
    expect(scheduling.children[0]).toMatchObject({
      label: 'SIDEBAR.CRM_CALENDAR',
      to: { name: 'crm_calendar_index' },
      activeOn: ['crm_calendar_index'],
    });
    expect(scheduling.children[1]).toMatchObject({
      label: 'BOOKING.PAGE.MENU',
      to: { name: 'settings_booking' },
      activeOn: ['settings_booking', 'settings_booking_results'],
    });
  });

  it('o subgrupo é recolhível e nasce fechado', () => {
    seat({});
    expect(schedulingOf(mountSidebar())).toMatchObject({
      collapsible: true,
      defaultCollapsed: true,
    });
  });

  it('agente comum com CRM vê Calendário, Meus horários e Meus números', () => {
    seat({ role: 'agent' });
    const wrapper = mountSidebar();
    expect(childrenOf(wrapper, 'CRM')).not.toContain('CRM Calendar');
    expect(schedulingOf(wrapper).children.map(child => child.name)).toEqual([
      'CRM Calendar',
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

  it('função só com Agendamento, sem CRM, vê o CRM só com o subgrupo, sem Kanban nem Calendário', () => {
    seat({ role: 'agent', customRoleId: 7, keys: ['agendamento_view'] });
    const wrapper = mountSidebar();
    expect(childrenOf(wrapper, 'CRM')).toEqual(['CRM Scheduling']);
    expect(schedulingOf(wrapper).children.map(child => child.name)).toEqual([
      'CRM Booking',
    ]);
  });

  it('flag desligada: o Calendário segue solto depois do Kanban, sem subgrupo, e a função só com Agendamento perde o CRM', () => {
    seat({ bookingV2: false });
    const wrapper = mountSidebar();
    const crm = childrenOf(wrapper, 'CRM');
    expect(crm.slice(0, 3)).toEqual([
      'CRM Kanban',
      'CRM Calendar',
      'CRM Dashboard',
    ]);
    expect(crm).not.toContain('CRM Scheduling');
    expect(
      wrapper
        .findAllComponents({ name: 'SidebarGroup' })
        .find(item => item.props('name') === 'CRM')
        .props('children')[1]
    ).toEqual({
      name: 'CRM Calendar',
      label: 'SIDEBAR.CRM_CALENDAR',
      to: { name: 'crm_calendar_index', params: undefined },
      activeOn: ['crm_calendar_index'],
    });

    seat({
      role: 'agent',
      customRoleId: 7,
      keys: ['agendamento_view'],
      bookingV2: false,
    });
    expect(childrenOf(mountSidebar(), 'CRM')).toBeUndefined();
  });

  it('calendário desligado na instalação: o Calendário também segue solto no CRM', () => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'false' };
    seat({});
    const crm = childrenOf(mountSidebar(), 'CRM');
    expect(crm.slice(0, 2)).toEqual(['CRM Kanban', 'CRM Calendar']);
    expect(crm).not.toContain('CRM Scheduling');
  });

  it('função sem CRM e sem Agendamento continua sem o grupo CRM', () => {
    seat({ role: 'agent', customRoleId: 7, keys: ['label_manage'] });
    expect(childrenOf(mountSidebar(), 'CRM')).toBeUndefined();
  });
});

// CRM › SLA (#1618): o SLA saiu de Configurações e mora no CRM; a função com
// sla_manage, a chave que a API do SLA confere, também vê a entrada.
describe('Sidebar: SLA no grupo CRM', () => {
  const comSla = keys => {
    seat({ role: 'agent', customRoleId: 7, keys });
    // Todas as flags, menos a do menu novo (#1617): este teste lê o menu de sempre.
    getters['accounts/isFeatureEnabledonAccount'] = ref(
      (_id, flag) => flag !== 'menu_lateral_novo'
    );
    return childrenOf(mountSidebar(), 'CRM');
  };

  it('função com CRM e sla_manage vê o SLA', () => {
    expect(comSla(['crm_view', 'sla_manage'])).toContain('CRM SLA');
  });

  it('função com crm_admin continua vendo o SLA', () => {
    expect(comSla(['crm_view', 'crm_admin'])).toContain('CRM SLA');
  });

  it('função com CRM sem chave de SLA continua sem o SLA', () => {
    expect(comSla(['crm_view'])).not.toContain('CRM SLA');
  });
});

// #2070: o item de Anúncios da Meta aparece para quem tem só meta_ads_manage (a função guarda só a chave mais alta).
describe('Sidebar: Anúncios da Meta em Campanhas', () => {
  const campanhasCom = keys => {
    seat({ role: 'agent', customRoleId: 7, keys });
    getters['accounts/isFeatureEnabledonAccount'] = ref(
      (_id, flag) => flag !== 'menu_lateral_novo'
    );
    return childrenOf(mountSidebar(), 'Campaigns') || [];
  };

  it('função só com meta_ads_manage vê o item', () => {
    expect(campanhasCom(['meta_ads_manage'])).toContain('Campaign Meta Ads');
  });

  it('função só com meta_ads_view continua vendo o item', () => {
    expect(campanhasCom(['meta_ads_view'])).toContain('Campaign Meta Ads');
  });

  it('função sem chave de Anúncios da Meta não vê o item', () => {
    expect(campanhasCom(['campaign_view'])).not.toContain('Campaign Meta Ads');
  });
});

// #2211 — com a chave lista_quem_espera, a busca e o lápis saem do menu (a busca mora no topo da lista
// e "Escrever" começa a conversa). Desligada, o menu fica como na main: a busca e o lápis continuam.
describe('Sidebar: busca e lápis com a lista nova (#2211)', () => {
  const comChave = ligada => {
    seat({ keys: ['administrator'] });
    getters['accounts/isFeatureEnabledonAccount'] = ref(
      (_conta, chave) => ligada && chave === 'lista_quem_espera'
    );
    return shallowMount(Sidebar, {
      global: {
        stubs: {
          RouterLink: {
            name: 'RouterLink',
            props: ['to'],
            template: '<a><slot /></a>',
          },
          SidebarGroup: {
            name: 'SidebarGroup',
            props: ['name', 'children'],
            template: '<li />',
          },
        },
      },
    });
  };
  const linkDaBusca = wrapper =>
    wrapper
      .findAllComponents({ name: 'RouterLink' })
      .filter(link => link.props('to')?.name === 'search');
  const lapis = wrapper => wrapper.find('compose-conversation-stub');

  it('desligada, mostra a busca e o lápis como na main', () => {
    const wrapper = comChave(false);
    expect(linkDaBusca(wrapper)).toHaveLength(1);
    expect(lapis(wrapper).exists()).toBe(true);
  });

  it('ligada, tira a busca e o lápis do menu', () => {
    const wrapper = comChave(true);
    expect(linkDaBusca(wrapper)).toHaveLength(0);
    expect(lapis(wrapper).exists()).toBe(false);
  });
});

describe('Sidebar: Seus posts em Crescer (#2304)', () => {
  const temSeusPosts = wrapper =>
    wrapper
      .findAllComponents({ name: 'SidebarGroup' })
      .some(item => item.props('name') === 'SeusPosts');
  const comFlag = ligada => {
    getters['accounts/isFeatureEnabledonAccount'] = ref(
      (_id, flag) => ligada && flag === 'seus_posts'
    );
  };

  it('administrador com a flag vê o item', () => {
    seat({});
    comFlag(true);
    expect(temSeusPosts(mountSidebar())).toBe(true);
  });

  it('função com posts_view e a flag vê o item', () => {
    seat({ role: 'agent', customRoleId: 3, keys: ['posts_view'] });
    comFlag(true);
    expect(temSeusPosts(mountSidebar())).toBe(true);
  });

  it('flag desligada: nem o administrador vê o item', () => {
    seat({});
    comFlag(false);
    expect(temSeusPosts(mountSidebar())).toBe(false);
  });

  it('sem a chave de posts: o item não aparece, mesmo com a flag', () => {
    seat({ role: 'agent', customRoleId: 3, keys: ['crm_view'] });
    comFlag(true);
    expect(temSeusPosts(mountSidebar())).toBe(false);
  });
});
