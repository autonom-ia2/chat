import { flushPromises, shallowMount } from '@vue/test-utils';
import { computed, ref } from 'vue';
import TrackedLinksPage from '../TrackedLinksPage.vue';

// The "Meta campaign names" block (#1034) is for who connects Meta ads: administrator or meta_ads_manage (#2070).
const granted = ref(['meta_ads_manage']);
// Anúncios da Meta (#1047): com a flag meta_ads_hub, o bloco vira atalho para a página nova.
const metaAdsHub = ref(false);
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => ref(true),
  usePermissionGranted: key => computed(() => granted.value.includes(key)),
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

  it('shows the block to who holds meta_ads_manage', async () => {
    granted.value = ['meta_ads_manage'];
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      true
    );
  });

  it('hides the block from who only views Meta ads', async () => {
    granted.value = ['meta_ads_view'];
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      false
    );
  });

  it('with Anúncios da Meta on, swaps the block for a shortcut to the new page', async () => {
    granted.value = ['meta_ads_manage'];
    metaAdsHub.value = true;
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      false
    );
    expect(wrapper.find('[data-meta-ads-moved]').exists()).toBe(true);
  });
});
