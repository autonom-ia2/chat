import { mount } from '@vue/test-utils';
import { nextTick, reactive, ref } from 'vue';
import SidebarSubGroup from '../SidebarSubGroup.vue';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { provideSidebarContext } from '../provider';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(1),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    shouldShow: () => true,
  }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    resolve: () => ({ path: '/' }),
    getRoutes: () => [],
  }),
}));

const children = [
  {
    name: 'Sales-1',
    label: 'Sales',
    to: { name: 'team_conversations' },
  },
];

const leafStub = {
  props: {
    label: { type: String, required: true },
    hideTreeLine: { type: Boolean, default: false },
    thinTreeLine: { type: Boolean, default: false },
  },
  template: '<li class="sidebar-leaf">{{ label }}</li>',
};

// CRM › Agendamento (#1288): recolhível que nasce fechado. `state` é reativo
// para o teste trocar a tela ativa sem montar de novo.
const schedulingChildren = [
  { name: 'CRM Calendar', label: 'Calendário', to: { name: 'calendar' } },
  { name: 'CRM Booking', label: 'Páginas e links', to: { name: 'booking' } },
];

const mountScheduling = (overrides = {}) => {
  const state = reactive({
    name: 'CRM:CRM Scheduling',
    label: 'Agendamento',
    icon: 'i-lucide-calendar-clock',
    children: schedulingChildren,
    isExpanded: true,
    collapsible: true,
    defaultCollapsed: true,
    activeChild: undefined,
    ...overrides,
  });
  const wrapper = mount(
    {
      components: { SidebarSubGroup },
      setup() {
        provideSidebarContext({});
        return { state };
      },
      template: '<SidebarSubGroup v-bind="state" />',
    },
    { global: { stubs: { SidebarGroupLeaf: leafStub } } }
  );
  return { wrapper, state };
};

const mountSubGroup = props => {
  return mount(
    {
      components: { SidebarSubGroup },
      setup() {
        provideSidebarContext({});
      },
      template: '<SidebarSubGroup v-bind="$attrs" />',
    },
    {
      attrs: {
        name: 'Conversation:Teams',
        label: 'Teams',
        icon: 'i-lucide-users',
        children,
        isExpanded: true,
        collapsible: true,
        ...props,
      },
      global: {
        stubs: {
          SidebarGroupLeaf: {
            props: {
              label: { type: String, required: true },
              hideTreeLine: { type: Boolean, default: false },
              thinTreeLine: { type: Boolean, default: false },
            },
            template:
              '<li class="sidebar-leaf" :data-hide-tree-line="String(hideTreeLine)" :data-thin-tree-line="String(thinTreeLine)">{{ label }}</li>',
          },
        },
      },
    }
  );
};

describe('SidebarSubGroup', () => {
  let localStorageStore;

  beforeEach(() => {
    localStorageStore = {};
    Object.defineProperty(window, 'localStorage', {
      value: {
        getItem: key => localStorageStore[key] || null,
        setItem: (key, value) => {
          localStorageStore[key] = String(value);
        },
        removeItem: key => {
          delete localStorageStore[key];
        },
        clear: () => {
          localStorageStore = {};
        },
      },
      configurable: true,
    });

    window.localStorage.clear();
  });

  it('shows the only child of a non-collapsible subgroup', () => {
    const wrapper = mountSubGroup({
      name: 'CRM:CRM Scheduling',
      label: 'Agendamento',
      icon: 'i-lucide-calendar-clock',
      collapsible: false,
      children: [
        {
          name: 'Booking',
          label: 'Páginas e links',
          to: { name: 'settings_booking' },
          activeOn: ['settings_booking', 'settings_booking_results'],
        },
      ],
    });

    const leaves = wrapper.findAll('.sidebar-leaf');
    expect(leaves).toHaveLength(1);
    expect(leaves[0].text()).toBe('Páginas e links');
    expect(leaves[0].isVisible()).toBe(true);
  });

  it('keeps collapsible sections expanded by default', () => {
    const wrapper = mountSubGroup();

    expect(wrapper.find('button').attributes('aria-expanded')).toBe('true');
    expect(wrapper.find('.sidebar-leaf').isVisible()).toBe(true);
  });

  it('renders the tree line on the separator, positioned relative to it', () => {
    const wrapper = mountSubGroup({ showTreeLine: true });
    const button = wrapper.find('button');

    expect(button.classes()).toContain('relative');
    expect(button.classes()).toContain('before:bg-n-slate-4');
    expect(button.classes()).toContain('before:-bottom-1');
  });

  it('renders the end curve on the last separator', () => {
    const wrapper = mountSubGroup({ showTreeLine: true, endTreeLine: true });
    const button = wrapper.find('button');

    expect(button.classes()).toContain('before:h-3');
    expect(button.classes()).toContain('after:border-b-2');
  });

  it('draws nested item tree lines via the leaf connectors', () => {
    const wrapper = mountSubGroup({ showTreeLine: true });

    expect(
      wrapper.find('.sidebar-leaf').attributes('data-hide-tree-line')
    ).toBe('false');
  });

  it('marks nested item connectors as thin', () => {
    const wrapper = mountSubGroup({ showTreeLine: true });

    expect(
      wrapper.find('.sidebar-leaf').attributes('data-thin-tree-line')
    ).toBe('true');
  });

  it('minimizes the section and stores it by account and section name', async () => {
    const wrapper = mountSubGroup();

    await wrapper.find('button').trigger('click');

    const storedSections = JSON.parse(
      window.localStorage.getItem(LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS)
    );
    expect(wrapper.find('button').attributes('aria-expanded')).toBe('false');
    expect(wrapper.find('.sidebar-leaf').isVisible()).toBe(false);
    expect(storedSections).toEqual({ '1:Conversation:Teams': true });
  });

  it('uses the stored minimized state when mounted again', () => {
    window.localStorage.setItem(
      LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS,
      JSON.stringify({ '1:Conversation:Teams': true })
    );

    const wrapper = mountSubGroup();

    expect(wrapper.find('button').attributes('aria-expanded')).toBe('false');
    expect(wrapper.find('.sidebar-leaf').isVisible()).toBe(false);
  });

  it('expands a stored minimized section when one of its children is active', () => {
    window.localStorage.setItem(
      LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS,
      JSON.stringify({ '1:Conversation:Teams': true })
    );

    const wrapper = mountSubGroup({ activeChild: children[0] });

    const storedSections = JSON.parse(
      window.localStorage.getItem(LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS)
    );
    expect(wrapper.find('button').attributes('aria-expanded')).toBe('true');
    expect(wrapper.find('.sidebar-leaf').isVisible()).toBe(true);
    expect(storedSections).toEqual({});
  });

  describe('defaultCollapsed (CRM › Agendamento, #1288)', () => {
    const storedSections = () =>
      JSON.parse(
        window.localStorage.getItem(
          LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS
        )
      );
    const isOpen = wrapper =>
      wrapper.find('button').attributes('aria-expanded') === 'true';
    // v-show direto no estilo: o isVisible() do test-utils não acompanha a
    // folha que some depois de ter aparecido.
    const visibleLeaves = wrapper =>
      wrapper
        .findAll('.sidebar-leaf')
        .filter(leaf => leaf.element.style.display !== 'none')
        .map(leaf => leaf.text());

    it('starts collapsed when nothing is stored', () => {
      const { wrapper } = mountScheduling();

      expect(isOpen(wrapper)).toBe(false);
      expect(visibleLeaves(wrapper)).toEqual([]);
      expect(storedSections()).toBeNull();
    });

    it('opens by itself on a child screen, without storing a choice, and closes again when leaving', async () => {
      const { wrapper, state } = mountScheduling({
        activeChild: schedulingChildren[0],
      });

      expect(isOpen(wrapper)).toBe(true);
      expect(visibleLeaves(wrapper)).toEqual(['Calendário', 'Páginas e links']);
      expect(storedSections()).toBeNull();

      state.activeChild = { name: 'CRM Kanban' };
      await nextTick();

      expect(isOpen(wrapper)).toBe(false);
      expect(visibleLeaves(wrapper)).toEqual([]);
    });

    it('opens when the route moves to a child after mount', async () => {
      const { wrapper, state } = mountScheduling();

      state.activeChild = schedulingChildren[1];
      await nextTick();

      expect(isOpen(wrapper)).toBe(true);
    });

    it('remembers a manual open, across screens and mounts', async () => {
      const { wrapper, state } = mountScheduling();

      await wrapper.find('button').trigger('click');

      expect(isOpen(wrapper)).toBe(true);
      expect(storedSections()).toEqual({ '1:CRM:CRM Scheduling': false });

      state.activeChild = schedulingChildren[0];
      await nextTick();
      state.activeChild = { name: 'CRM Kanban' };
      await nextTick();

      expect(isOpen(wrapper)).toBe(true);
      expect(isOpen(mountScheduling().wrapper)).toBe(true);
    });

    it('remembers a manual close made on a child screen', async () => {
      const { wrapper, state } = mountScheduling({
        activeChild: schedulingChildren[0],
      });

      await wrapper.find('button').trigger('click');

      expect(isOpen(wrapper)).toBe(false);
      expect(storedSections()).toEqual({ '1:CRM:CRM Scheduling': true });

      state.activeChild = schedulingChildren[1];
      await nextTick();

      expect(isOpen(wrapper)).toBe(false);
    });

    it('opens again when coming back to a child screen after a manual close, and keeps the stored close for the other screens', async () => {
      const { wrapper, state } = mountScheduling({
        activeChild: schedulingChildren[0],
      });
      await wrapper.find('button').trigger('click');

      state.activeChild = { name: 'CRM Kanban' };
      await nextTick();
      expect(isOpen(wrapper)).toBe(false);

      state.activeChild = schedulingChildren[0];
      await nextTick();
      expect(isOpen(wrapper)).toBe(true);
      expect(storedSections()).toEqual({ '1:CRM:CRM Scheduling': true });

      state.activeChild = { name: 'CRM Kanban' };
      await nextTick();
      expect(isOpen(wrapper)).toBe(false);
    });

    it('follows a choice made in another tab', async () => {
      const { wrapper } = mountScheduling();

      window.localStorage.setItem(
        LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS,
        JSON.stringify({ '1:CRM:CRM Scheduling': false })
      );
      window.dispatchEvent(
        new StorageEvent('storage', {
          key: LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS,
        })
      );
      await nextTick();

      expect(isOpen(wrapper)).toBe(true);
    });

    it('closes again after a manual open followed by a manual close', async () => {
      const { wrapper } = mountScheduling();

      await wrapper.find('button').trigger('click');
      await wrapper.find('button').trigger('click');

      expect(isOpen(wrapper)).toBe(false);
      expect(isOpen(mountScheduling().wrapper)).toBe(false);
    });

    it('does not change subgroups without the prop: open by default, close stores true, reopen clears the key', async () => {
      const { wrapper } = mountScheduling({ defaultCollapsed: false });

      expect(isOpen(wrapper)).toBe(true);
      expect(storedSections()).toBeNull();

      await wrapper.find('button').trigger('click');
      expect(isOpen(wrapper)).toBe(false);
      expect(storedSections()).toEqual({ '1:CRM:CRM Scheduling': true });

      await wrapper.find('button').trigger('click');
      expect(isOpen(wrapper)).toBe(true);
      expect(storedSections()).toEqual({});
    });

    it('does not change subgroups without the prop: the active child still clears a stored close', () => {
      window.localStorage.setItem(
        LOCAL_STORAGE_KEYS.SIDEBAR_MINIMIZED_SECTIONS,
        JSON.stringify({ '1:CRM:CRM Scheduling': true })
      );
      const { wrapper } = mountScheduling({
        defaultCollapsed: false,
        activeChild: schedulingChildren[0],
      });

      expect(isOpen(wrapper)).toBe(true);
      expect(storedSections()).toEqual({});
    });
  });
});
