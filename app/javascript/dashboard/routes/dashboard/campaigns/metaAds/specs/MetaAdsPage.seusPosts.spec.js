import { computed, ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import MetaAdsPage from '../MetaAdsPage.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Seus posts virou página própria (#2302, F1 #2304): com a flag seus_posts, a aba sai de Anúncios da Meta e o
// endereço antigo (?aba=organico) leva à página nova, só para quem pode abri-la.
const flags = ref({});
const granted = ref([]);
const routing = vi.hoisted(() => ({ query: {}, replace: vi.fn() }));

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { get: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' }, query: routing.query }),
  useRouter: () => ({ replace: routing.replace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () =>
    computed(() => (_accountId, flag) => Boolean(flags.value[flag])),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: key => computed(() => granted.value.includes(key)),
}));

const mountPage = async () => {
  CrmMetaAdsConnectionAPI.get.mockResolvedValue({
    data: { configured: true, status: 'active', ad_account: { id: 'act_1' } },
  });
  const wrapper = shallowMount(MetaAdsPage, {
    global: { mocks: { $t: key => key } },
  });
  await flushPromises();
  return wrapper;
};
// Com uma aba só, a barra de abas nem aparece.
const abas = wrapper => {
  const barra = wrapper.findComponent({ name: 'MetaAdsViewTabs' });
  return barra.exists() ? barra.props('views') : [];
};

describe('MetaAdsPage · Seus posts em página própria (#2304)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    flags.value = { meta_ads_organico: true };
    granted.value = ['meta_ads_view', 'posts_view'];
    routing.query = { aba: 'organico' };
  });

  it('com seus_posts, o endereço antigo leva à página nova e a aba sai', async () => {
    flags.value = { meta_ads_organico: true, seus_posts: true };
    const wrapper = await mountPage();

    expect(routing.replace).toHaveBeenCalledWith({
      name: 'seus_posts_index',
      params: { accountId: '18' },
    });
    expect(abas(wrapper)).not.toContain('organico');
  });

  it('flags que chegam depois da tela montar (link direto) também levam à página nova', async () => {
    await mountPage();
    expect(routing.replace).not.toHaveBeenCalledWith(
      expect.objectContaining({ name: 'seus_posts_index' })
    );

    flags.value = { meta_ads_organico: true, seus_posts: true };
    await flushPromises();

    expect(routing.replace).toHaveBeenCalledWith({
      name: 'seus_posts_index',
      params: { accountId: '18' },
    });
  });

  it('sem posts_view, fica em Anúncios com a aba de antes', async () => {
    flags.value = { meta_ads_organico: true, seus_posts: true };
    granted.value = ['meta_ads_view'];
    const wrapper = await mountPage();

    expect(routing.replace).not.toHaveBeenCalledWith(
      expect.objectContaining({ name: 'seus_posts_index' })
    );
    expect(abas(wrapper)).toContain('organico');
  });

  it('sem seus_posts, a aba de antes continua', async () => {
    const wrapper = await mountPage();

    expect(routing.replace).not.toHaveBeenCalledWith(
      expect.objectContaining({ name: 'seus_posts_index' })
    );
    expect(abas(wrapper)).toContain('organico');
  });
});
