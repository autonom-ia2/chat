import { computed } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import MetaAdsPage from '../MetaAdsPage.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Criar anúncio sem conta de anúncios (#2338): a criação manda para a Conexão com `?volta=criar`. A página relê a
// conexão (a da memória pode estar velha) e, escolhida a conta, volta para criar.
const routing = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  return {
    route: reactive({ params: { accountId: '18' }, query: {} }),
    replace: vi.fn(),
  };
});

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { get: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => routing.route,
  useRouter: () => ({ replace: routing.replace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => () => false),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => computed(() => true),
}));

const WITHOUT_AD_ACCOUNT = {
  configured: true,
  status: 'active',
  mode: 'facebook_login',
  verified_at: null,
  ad_account: null,
  destinations: { whatsapp: true },
  sales_signal: { enabled: true },
};
const WITH_AD_ACCOUNT = {
  ...WITHOUT_AD_ACCOUNT,
  verified_at: '2026-10-28T12:00:00Z',
  ad_account: { id: 'act_1', name: 'Loja' },
};

// O endereço é um só para todos os testes: a página de um teste anterior, ainda montada, reagiria à mudança dele.
let mounted = null;
const mountPage = async () => {
  mounted = shallowMount(MetaAdsPage, {
    global: { mocks: { $t: key => key } },
  });
  await flushPromises();
  return mounted;
};

describe('MetaAdsPage · volta para criar anúncio (#2338)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    routing.route.query = {};
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
  });

  it('rereads the connection when creation sends the person to choose the ad account', async () => {
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: WITH_AD_ACCOUNT });
    await mountPage();
    expect(CrmMetaAdsConnectionAPI.get).toHaveBeenCalledTimes(1);

    CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: WITHOUT_AD_ACCOUNT });
    routing.route.query = { aba: 'conexao', volta: 'criar' };
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.get).toHaveBeenCalledTimes(2);
  });

  it('after the ad account is saved, goes back to creating the ad', async () => {
    routing.route.query = { aba: 'conexao', volta: 'criar' };
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: WITHOUT_AD_ACCOUNT });
    const wrapper = await mountPage();

    const step = wrapper.findComponent({ name: 'MetaAdsAccountStep' });
    expect(step.exists()).toBe(true);
    step.vm.$emit('saved', WITH_AD_ACCOUNT);
    await flushPromises();

    expect(routing.replace).toHaveBeenLastCalledWith({
      query: { aba: 'resultado', criar: 'novo' },
    });
  });

  it('without any connection, goes through signing in and still returns to creating the ad', async () => {
    routing.route.query = { aba: 'conexao', volta: 'criar' };
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({
      data: { configured: false },
    });
    const wrapper = await mountPage();
    expect(CrmMetaAdsConnectionAPI.get).toHaveBeenCalledTimes(1);

    wrapper.findComponent({ name: 'MetaAdsHero' }).vm.$emit('start');
    await flushPromises();
    wrapper
      .findComponent({ name: 'MetaAdsConnectStep' })
      .vm.$emit('facebookLogin', WITHOUT_AD_ACCOUNT);
    await flushPromises();
    wrapper
      .findComponent({ name: 'MetaAdsAccountStep' })
      .vm.$emit('saved', WITH_AD_ACCOUNT);
    await flushPromises();

    expect(routing.replace).toHaveBeenLastCalledWith({
      query: { aba: 'resultado', criar: 'novo' },
    });
  });

  // "Ligar a conta de anúncios" na criação só muda o endereço (`?aba=conexao`): a aba na tela tem de acompanhar,
  // mesmo quando a conexão relida já está completa.
  it('shows the tab the address asks for when it changes after loading', async () => {
    routing.route.query = { aba: 'resultado' };
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: WITH_AD_ACCOUNT });
    const wrapper = await mountPage();
    const tabs = () => wrapper.findComponent({ name: 'MetaAdsViewTabs' });
    expect(tabs().props('active')).toBe('resultado');

    routing.route.query = { aba: 'conexao', volta: 'criar' };
    await flushPromises();

    expect(tabs().props('active')).toBe('conexao');
  });

  it('changing tab drops the pending return', async () => {
    routing.route.query = { aba: 'resultado', volta: 'criar', periodo: '7d' };
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: WITH_AD_ACCOUNT });
    const wrapper = await mountPage();

    wrapper
      .findComponent({ name: 'MetaAdsViewTabs' })
      .vm.$emit('choose', 'conexao');
    await flushPromises();

    expect(routing.replace).toHaveBeenLastCalledWith({
      query: { aba: 'conexao', periodo: '7d' },
    });
  });

  it('coming back from the comments of an ad still returns to that ad', async () => {
    routing.route.query = { aba: 'conexao', volta: '120000000000001' };
    CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: WITHOUT_AD_ACCOUNT });
    const wrapper = await mountPage();

    wrapper
      .findComponent({ name: 'MetaAdsAccountStep' })
      .vm.$emit('saved', WITH_AD_ACCOUNT);
    await flushPromises();

    expect(routing.replace).toHaveBeenLastCalledWith({
      query: { aba: 'resultado', anuncio: '120000000000001' },
    });
  });
});
