import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidebarGroup from '../SidebarGroup.vue';

// O grupo repassa ao subgrupo o "nasce fechado" e a tela ativa (#1288): é o
// que faz CRM › Agendamento abrir sozinho no Calendário.
const route = { path: '/', name: '', params: {} };
const isCollapsed = ref(false);
const activePopover = ref(null);

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('../provider', () => ({
  useSidebarContext: () => ({
    expandedItem: ref('CRM'),
    setExpandedItem: vi.fn(),
    resolvePath: to => `/${to.name}`,
    resolvePermissions: () => [],
    resolveFeatureFlag: () => '',
    isAllowed: () => true,
    isCollapsed,
    isResizing: ref(false),
  }),
  usePopoverState: () => ({
    activePopover,
    setActivePopover: name => {
      activePopover.value = name;
    },
    closeActivePopover: vi.fn(),
    scheduleClose: vi.fn(),
    cancelClose: vi.fn(),
  }),
}));

const leaf = name => ({ name, label: name, to: { name, params: {} } });

const children = [
  leaf('CRM Kanban'),
  {
    name: 'CRM Scheduling',
    label: 'Agendamento',
    icon: 'i-lucide-calendar-clock',
    collapsible: true,
    defaultCollapsed: true,
    showTreeLine: true,
    children: [leaf('CRM Calendar'), leaf('CRM Booking')],
  },
  leaf('CRM Dashboard'),
];

const stub = (name, props) => ({
  name,
  props,
  inheritAttrs: false,
  template: '<li />',
});

const mountGroup = () =>
  mount(SidebarGroup, {
    props: {
      name: 'CRM',
      label: 'CRM',
      icon: 'i-lucide-kanban-square',
      children,
    },
    global: {
      stubs: {
        Policy: { template: '<li><slot /></li>' },
        Icon: true,
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        SidebarGroupHeader: true,
        SidebarGroupLeaf: stub('SidebarGroupLeaf', ['label', 'active']),
        SidebarSubGroup: stub('SidebarSubGroup', [
          'name',
          'collapsible',
          'defaultCollapsed',
          'showTreeLine',
          'endTreeLine',
          'activeChild',
        ]),
        SidebarCollapsedPopover: stub('SidebarCollapsedPopover', [
          'children',
          'activeChild',
        ]),
      },
    },
  });

describe('SidebarGroup: subgrupo que nasce fechado', () => {
  beforeEach(() => {
    isCollapsed.value = false;
    activePopover.value = null;
    route.path = '/';
  });

  it('repassa collapsible, defaultCollapsed e a linha da árvore ao subgrupo', () => {
    const subGroup = mountGroup().findComponent({ name: 'SidebarSubGroup' });

    expect(subGroup.props()).toMatchObject({
      name: 'CRM:CRM Scheduling',
      collapsible: true,
      defaultCollapsed: true,
      showTreeLine: true,
      endTreeLine: false,
    });
  });

  it('entrega ao subgrupo o filho ativo quando a tela é o Calendário', () => {
    route.path = '/CRM Calendar';
    const subGroup = mountGroup().findComponent({ name: 'SidebarSubGroup' });

    expect(subGroup.props('activeChild').name).toBe('CRM Calendar');
  });

  it('com a barra recolhida, o popover recebe o subgrupo e o filho ativo', async () => {
    isCollapsed.value = true;
    route.path = '/CRM Calendar';
    const wrapper = mountGroup();

    await wrapper.find('[data-sidebar-group-trigger]').trigger('mouseenter');
    const popover = wrapper.findComponent({ name: 'SidebarCollapsedPopover' });

    expect(popover.props('children').map(child => child.name)).toEqual([
      'CRM Kanban',
      'CRM Scheduling',
      'CRM Dashboard',
    ]);
    expect(popover.props('activeChild').name).toBe('CRM Calendar');
  });
});
