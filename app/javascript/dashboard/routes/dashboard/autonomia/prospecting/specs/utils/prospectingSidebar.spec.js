// Atalho Configurações no menu Prospecção (#682): aparece para quem vê a
// Prospecção e pode abrir a página, fica marcado com a página aberta e leva à
// mesma rota da entrada em Configurações da conta.
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidebarGroup from 'dashboard/components-next/sidebar/SidebarGroup.vue';
import { provideSidebarContext } from 'dashboard/components-next/sidebar/provider';
import { prospectingSidebarItems } from '../../utils/prospectingSidebar';

const current = vi.hoisted(() => ({ routeName: '', userPermissions: [] }));

// As permissões de cada rota, como no roteador (autonomia.routes.js e
// settings/prospecting/prospecting.routes.js).
const ROUTE_PERMISSIONS = vi.hoisted(() => ({
  autonomia_prospecting_search: [
    'administrator',
    'prospecting_view',
    'prospecting_manage',
  ],
  autonomia_prospecting_lists: [
    'administrator',
    'prospecting_view',
    'prospecting_manage',
  ],
  settings_prospecting_index: ['administrator', 'prospecting_manage'],
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: current.routeName,
    path: `/app/accounts/1/${current.routeName}`,
    params: { accountId: 1 },
  }),
  useRouter: () => ({
    resolve: to => ({
      path: `/app/accounts/1/${to.name}`,
      meta: { permissions: ROUTE_PERMISSIONS[to.name] },
    }),
    getRoutes: () => [],
    push: vi.fn(),
  }),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    shouldShow: (_flag, permissions) =>
      permissions.some(permission =>
        current.userPermissions.includes(permission)
      ),
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(1),
}));

const t = key => key;
const accountScopedRoute = name => ({ name, params: { accountId: 1 } });
const items = isVisible =>
  prospectingSidebarItems({ isVisible, t, accountScopedRoute });

const LeafStub = {
  props: {
    label: { type: String, required: true },
    to: { type: Object, required: true },
    active: { type: Boolean, default: false },
  },
  template:
    '<li class="leaf" :data-route="to.name" :data-active="String(active)">{{ label }}</li>',
};

const mountMenu = ({ routeName, permissions }) => {
  current.routeName = routeName;
  current.userPermissions = permissions;
  const [menu] = items(true);
  return mount(
    {
      components: { SidebarGroup },
      setup() {
        provideSidebarContext({
          expandedItem: ref('Prospecting'),
          setExpandedItem: vi.fn(),
          isCollapsed: ref(false),
          isResizing: ref(false),
        });
        return { menu };
      },
      template: '<SidebarGroup v-bind="menu" />',
    },
    {
      global: {
        stubs: {
          SidebarGroupLeaf: LeafStub,
          SidebarGroupHeader: true,
          Policy: { template: '<li><slot /></li>' },
        },
      },
    }
  );
};

const leaf = (wrapper, routeName) =>
  wrapper.find(`[data-route="${routeName}"]`);

describe('menu Prospecção da barra lateral', () => {
  it('não aparece para quem não vê a Prospecção', () => {
    expect(items(false)).toEqual([]);
  });

  it('tem Buscar leads, Listas e Configurações, nesta ordem', () => {
    const [menu] = items(true);

    expect(menu.children.map(child => child.label)).toEqual([
      'SIDEBAR.PROSPECTING_SEARCH',
      'SIDEBAR.PROSPECTING_LISTS',
      'SIDEBAR.PROSPECTING_SETTINGS',
    ]);
  });

  it('o atalho leva à mesma página de Configurações > Prospecção', () => {
    const settings = items(true)[0].children[2];

    expect(settings.to).toEqual({
      name: 'settings_prospecting_index',
      params: { accountId: 1 },
    });
  });

  it('com a página de configurações aberta, o atalho fica marcado', () => {
    const wrapper = mountMenu({
      routeName: 'settings_prospecting_index',
      permissions: ['prospecting_manage'],
    });

    expect(
      leaf(wrapper, 'settings_prospecting_index').attributes('data-active')
    ).toBe('true');
    expect(
      leaf(wrapper, 'autonomia_prospecting_search').attributes('data-active')
    ).toBe('false');
  });

  it('na busca, o atalho aparece e não fica marcado', () => {
    const wrapper = mountMenu({
      routeName: 'autonomia_prospecting_search',
      permissions: ['administrator'],
    });

    expect(
      leaf(wrapper, 'settings_prospecting_index').attributes('data-active')
    ).toBe('false');
    expect(
      leaf(wrapper, 'autonomia_prospecting_search').attributes('data-active')
    ).toBe('true');
  });

  it('quem só vê a Prospecção não recebe o atalho de uma página que não abre', () => {
    const wrapper = mountMenu({
      routeName: 'autonomia_prospecting_search',
      permissions: ['prospecting_view'],
    });

    expect(leaf(wrapper, 'autonomia_prospecting_search').exists()).toBe(true);
    expect(leaf(wrapper, 'settings_prospecting_index').exists()).toBe(false);
  });
});
