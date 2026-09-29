import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createRouter, createMemoryHistory } from 'vue-router';
import RelationshipsHome from 'dashboard/routes/dashboard/relationships/RelationshipsHome.vue';
import RelationshipBreadcrumb from '../RelationshipBreadcrumb.vue';
import en from 'dashboard/i18n/locale/en/relationships.json';
import pt from 'dashboard/i18n/locale/pt_BR/relationships.json';

const access = vi.hoisted(() => ({
  navigation: true,
  companies: true,
  manage: true,
  media: true,
  attributes: true,
}));
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({
    navigationEnabled: ref(access.navigation),
    accountId: ref(17),
    mediaEnabled: ref(access.media),
    attributesEnabled: ref(access.attributes),
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flag !== 'companies' || access.companies,
  }),
}));
vi.mock('dashboard/components/policy.vue', () => ({
  default: {
    props: ['permissions'],
    setup: () => ({ access }),
    template:
      '<slot v-if="access.manage || !permissions.includes(\'attribute_manage\')" />',
  },
}));
const names = [
  'relationships_home',
  'contacts_dashboard_index',
  'companies_dashboard_index',
  'attributes_list',
];
const mountPage = async (
  component,
  props = {},
  name = 'relationships_home'
) => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: names.map(routeName => ({
      name: routeName,
      path: `/app/accounts/:accountId/${routeName}`,
      component: { template: '<div />' },
    })),
  });
  await router.push({ name, params: { accountId: 17 } });
  const wrapper = mount(component, {
    props,
    global: { plugins: [router], mocks: { $t: key => key } },
  });
  await flushPromises();
  return { wrapper, router };
};
beforeEach(() => {
  Object.assign(access, {
    navigation: true,
    companies: true,
    manage: true,
    media: true,
    attributes: true,
  });
});

it('renders one explicit accessible destination per card, with the current account', async () => {
  const { wrapper, router } = await mountPage(RelationshipsHome);
  expect(wrapper.findAll('article')).toHaveLength(3);
  const links = wrapper.findAll('article a');
  expect(links.map(link => link.text())).toEqual([
    'RELATIONSHIPS.OPEN_CONTACTS',
    'RELATIONSHIPS.OPEN_COMPANIES',
    'RELATIONSHIPS.OPEN_ATTRIBUTES',
  ]);
  expect(
    links.every(link => link.attributes('href').includes('/accounts/17/'))
  ).toBe(true);
  expect(wrapper.find('article a button').exists()).toBe(false);
  await links[1].trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.name).toBe('companies_dashboard_index');
  expect(wrapper.findAll('article ul li')).toHaveLength(9);
  wrapper.unmount();
});

it('keeps the feature and management gates instead of adding a disabled or unauthorized card', async () => {
  access.companies = false;
  access.manage = false;
  const { wrapper } = await mountPage(RelationshipsHome);
  expect(wrapper.findAll('article')).toHaveLength(1);
  expect(wrapper.find('article a').text()).toBe('RELATIONSHIPS.OPEN_CONTACTS');
  wrapper.unmount();
});

it('does not render the new home or breadcrumb when the navigation flag is off', async () => {
  access.navigation = false;
  const home = await mountPage(RelationshipsHome);
  const crumb = await mountPage(RelationshipBreadcrumb);
  expect(home.wrapper.find('main').exists()).toBe(false);
  expect(crumb.wrapper.find('nav').exists()).toBe(false);
  home.wrapper.unmount();
  crumb.wrapper.unmount();
});

it('keeps a complete breadcrumb with a real link and a distinct current record', async () => {
  const { wrapper, router } = await mountPage(RelationshipBreadcrumb, {
    items: [
      {
        key: 'CONTACTS',
        to: { name: 'contacts_dashboard_index', params: { accountId: 17 } },
      },
      { label: 'Contato demonstrativo' },
    ],
  });
  expect(wrapper.find('span[aria-current="page"]').text()).toBe(
    'Contato demonstrativo'
  );
  expect(wrapper.findAll('a')).toHaveLength(2);
  await wrapper.findAll('a')[0].trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.name).toBe('relationships_home');
  wrapper.unmount();
});

it('places the legacy attributes route under Relationships without rewriting its URL', async () => {
  const { wrapper, router } = await mountPage(
    RelationshipBreadcrumb,
    {},
    'attributes_list'
  );
  expect(wrapper.find('span[aria-current="page"]').text()).toBe(
    'RELATIONSHIPS.ATTRIBUTES'
  );
  expect(router.currentRoute.value.name).toBe('attributes_list');
  wrapper.unmount();
});

it('keeps the two maintained relationship catalogs in sync and contextual actions explicit', () => {
  const leaves = (value, prefix = '') =>
    Object.entries(value)
      .flatMap(([key, child]) =>
        typeof child === 'object'
          ? leaves(child, `${prefix}${key}.`)
          : [`${prefix}${key}`]
      )
      .sort();
  expect(leaves(pt)).toEqual(leaves(en));
  expect(pt.RELATIONSHIPS.CREATE).not.toBe(pt.RELATIONSHIPS.CONFIGURE);
  expect(pt.RELATIONSHIPS.SAVE_ATTRIBUTE).not.toBe(
    pt.RELATIONSHIPS.SAVE_CONFIGURATION
  );
  expect(pt.RELATIONSHIPS.MEDIA.TAB).toBe('Mídias');
  expect(pt.RELATIONSHIPS.MEDIA.PDF).toBe('PDF');
});

it('does not advertise company media or presentation controls when their independent flags are off', async () => {
  access.media = false;
  access.attributes = false;
  const { wrapper } = await mountPage(RelationshipsHome);
  expect(wrapper.text()).not.toContain(
    'RELATIONSHIPS.CARD_DETAILS.COMPANIES.MEDIA'
  );
  expect(wrapper.text()).not.toContain(
    'RELATIONSHIPS.CARD_DETAILS.ATTRIBUTES.MEDIA'
  );
  expect(wrapper.text()).toContain(
    'RELATIONSHIPS.CARD_DETAILS.COMPANIES.BASIC_DESCRIPTION'
  );
  wrapper.unmount();
});
