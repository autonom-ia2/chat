import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import StoreAPI from 'dashboard/api/autonomia/store';
import en from 'dashboard/i18n/locale/en/financial.json';
import fixtures from '../../../../../../../spec/fixtures/autonomia_store/contracts.v1.json';
import StoreCatalogPage from './StoreCatalogPage.vue';

const route = reactive({ params: { accountId: '17' }, query: {} });
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('dashboard/api/autonomia/store', () => ({
  default: { catalog: vi.fn() },
}));

const mounted = [];
const render = (type = 'SuperAdmin') => {
  const wrapper = mount(StoreCatalogPage, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        createStore({ getters: { getCurrentUser: () => ({ type }) } }),
      ],
      stubs: {
        StoreServiceDialog: { template: '<div />', methods: { open: vi.fn() } },
        StoreFeaturesDialog: {
          template: '<div />',
          methods: { open: vi.fn() },
        },
        StoreCheckoutReturn: { template: '<div />' },
        StoreOwnedServices: { template: '<div />' },
      },
    },
  });
  mounted.push(wrapper);
  return wrapper;
};

afterEach(() => {
  mounted.splice(0).forEach(wrapper => wrapper.unmount());
});
beforeEach(() => {
  route.params.accountId = '17';
  StoreAPI.catalog.mockResolvedValue({ data: fixtures.catalog });
});

describe('Store catalog access and lifecycle', () => {
  it.each(['User', undefined, 'Administrator'])(
    'does not fetch the catalog for %s',
    async type => {
      render(type === undefined ? null : type);
      await flushPromises();
      expect(StoreAPI.catalog).not.toHaveBeenCalled();
    }
  );

  it('loads the official catalog and displays service cards for the superadmin', async () => {
    const wrapper = render();
    await flushPromises();
    expect(StoreAPI.catalog).toHaveBeenCalledWith(1, expect.any(AbortSignal));
    expect(wrapper.text()).toContain(fixtures.catalog.data[0].service.name);
    expect(wrapper.findAll('article')).toHaveLength(
      fixtures.catalog.data.length
    );
    expect(wrapper.text()).not.toContain('Checkout');
  });

  it('renders the empty state without fabricated services', async () => {
    StoreAPI.catalog.mockResolvedValue({
      data: { data: [], pagination: { page: 1, totalPages: 0 } },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain('No published services found.');
    expect(wrapper.findAll('article')).toHaveLength(0);
  });

  it('renders sanitized error and expired session states', async () => {
    StoreAPI.catalog.mockRejectedValue({
      response: { status: 401, data: { error: 'upstream-secret-example' } },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain('Your Auth session expired.');
    expect(wrapper.text()).not.toContain('upstream-secret-example');
  });

  it('aborts the old request and ignores its result when the account changes', async () => {
    let resolveOld;
    StoreAPI.catalog.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = render();
    const oldSignal = StoreAPI.catalog.mock.calls[0][1];
    route.params.accountId = '18';
    await flushPromises();
    expect(oldSignal.aborted).toBe(true);
    resolveOld({ data: { data: [], pagination: { page: 1, totalPages: 0 } } });
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(
      fixtures.catalog.data.length
    );
  });
});
