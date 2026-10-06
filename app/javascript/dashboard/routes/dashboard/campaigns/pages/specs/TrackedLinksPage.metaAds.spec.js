import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import TrackedLinksPage from '../TrackedLinksPage.vue';

// The "Meta campaign names" block (#1034) is for account administrators only.
const isAdmin = ref(true);
// Anúncios da Meta (#1047): com a flag meta_ads_hub, o bloco vira atalho para a página nova.
const metaAdsHub = ref(false);
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin }),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => ref(true),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue(true) }),
  useMapGetter: name => {
    if (name === 'accounts/isFeatureEnabledonAccount') {
      return ref(
        (_accountId, flag) => flag === 'meta_ads_hub' && metaAdsHub.value
      );
    }
    if (name === 'getCurrentAccountId') return ref(1);
    return ref([{ id: 38, name: 'WhatsApp Vendas' }]);
  },
}));
vi.mock('dashboard/api/ctwaTrackedLinks', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: { payload: [] } }) },
}));

const mountPage = async () => {
  const wrapper = shallowMount(TrackedLinksPage, {
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  });
  await flushPromises();
  return wrapper;
};

describe('TrackedLinksPage · Meta campaign names block', () => {
  beforeEach(() => {
    metaAdsHub.value = false;
  });

  it('shows the block to an administrator', async () => {
    isAdmin.value = true;
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      true
    );
  });

  it('hides the block from anyone else', async () => {
    isAdmin.value = false;
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      false
    );
  });

  it('with Anúncios da Meta on, swaps the block for a shortcut to the new page', async () => {
    isAdmin.value = true;
    metaAdsHub.value = true;
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      false
    );
    expect(wrapper.find('[data-meta-ads-moved]').exists()).toBe(true);
  });
});
