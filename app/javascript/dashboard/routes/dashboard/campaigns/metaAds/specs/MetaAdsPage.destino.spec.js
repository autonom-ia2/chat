import { computed } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import MetaAdsPage from '../MetaAdsPage.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Destino (#2338): anúncio levando ao site e nenhuma página ligada — o passo do Destino fica pendente na lista de
// passos. Ligar a página ali mesmo relê a conexão, e a pendência some.
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { get: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' }, query: { aba: 'conexao' } }),
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => () => false),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => computed(() => true),
}));

const connection = (destinations, sitePagesCount) => ({
  configured: true,
  status: 'active',
  mode: 'facebook_login',
  verified_at: '2026-10-28T12:00:00Z',
  ad_account: { id: 'act_1', name: 'Loja' },
  pixel: { id: 'px_1', name: 'Pixel' },
  destinations,
  site_pages_count: sitePagesCount,
  sales_signal: { enabled: true },
});
const mountPage = async () => {
  const wrapper = shallowMount(MetaAdsPage, {
    global: { mocks: { $t: key => key } },
  });
  await flushPromises();
  return wrapper;
};
const pending = wrapper =>
  wrapper
    .findComponent({ name: 'MetaAdsChecklist' })
    .props('destinationsPending');

describe('MetaAdsPage · página do site no Destino (#2338)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('marks the destination step pending when the ad leads to the site and no page is linked', async () => {
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({
      data: connection({ whatsapp: true, site: true }, 0),
    });
    const wrapper = await mountPage();

    expect(pending(wrapper)).toBe(true);
  });

  it('nothing is pending with a page linked, or when the ad does not lead to the site', async () => {
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({
      data: connection({ whatsapp: true, site: true }, 1),
    });
    expect(pending(await mountPage())).toBe(false);

    CrmMetaAdsConnectionAPI.get.mockResolvedValue({
      data: connection({ whatsapp: true, site: false }, 0),
    });
    expect(pending(await mountPage())).toBe(false);
  });

  it('rereads the connection when a page is linked in the destination step', async () => {
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({
      data: connection({ whatsapp: true, site: true }, 0),
    });
    const wrapper = await mountPage();
    wrapper.findComponent({ name: 'MetaAdsChecklist' }).vm.$emit('change', 3);
    await flushPromises();

    CrmMetaAdsConnectionAPI.get.mockResolvedValue({
      data: connection({ whatsapp: true, site: true }, 1),
    });
    wrapper
      .findComponent({ name: 'MetaAdsDestinationsStep' })
      .vm.$emit('pageLinked');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.get).toHaveBeenCalledTimes(2);
    expect(pending(wrapper)).toBe(false);
  });
});
