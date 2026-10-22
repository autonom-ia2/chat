import { computed, ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import MetaAdsPage from '../MetaAdsPage.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Anúncios sem login (#1960): a página só troca de tela com a flag ligada, o servidor dizendo
// que vale e sem conta de anúncios conectada. Fora disso, tudo como antes.
const flags = ref({ anuncios_sem_login: true });
// Chaves que a pessoa tem (#2070): quem conecta é quem tem meta_ads_manage (o administrador também passa).
const granted = ref(['meta_ads_manage']);
const routing = vi.hoisted(() => ({ query: {} }));

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { get: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' }, query: routing.query }),
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () =>
    computed(() => (_accountId, flag) => Boolean(flags.value[flag])),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: key => computed(() => granted.value.includes(key)),
}));

const WHATSAPP_RESULT = {
  enabled: true,
  official_inboxes: [{ id: 7, name: 'Vendas', phone: '+5511988887777' }],
  ad_touch: true,
};

const reply = connection =>
  CrmMetaAdsConnectionAPI.get.mockResolvedValue({ data: connection });

const mountPage = async () => {
  const wrapper = shallowMount(MetaAdsPage, {
    global: { mocks: { $t: key => key } },
  });
  await flushPromises();
  return wrapper;
};

describe('MetaAdsPage · Anúncios sem login (#1960)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    flags.value = { anuncios_sem_login: true };
    granted.value = ['meta_ads_manage'];
    routing.query = {};
  });

  it('opens ready, without login, when the flag is on and nothing is connected', async () => {
    reply({ configured: false, whatsapp_result: WHATSAPP_RESULT });
    const wrapper = await mountPage();

    const semLogin = wrapper.findComponent({ name: 'AnunciosSemLogin' });
    expect(semLogin.exists()).toBe(true);
    expect(semLogin.props('result')).toEqual(WHATSAPP_RESULT);
    expect(semLogin.props('readOnly')).toBe(false);
    expect(wrapper.findComponent({ name: 'MetaAdsHero' }).exists()).toBe(false);
  });

  it('passes read-only to who only views (meta_ads_view)', async () => {
    granted.value = ['meta_ads_view'];
    reply({ configured: false, whatsapp_result: WHATSAPP_RESULT });
    const wrapper = await mountPage();

    expect(
      wrapper.findComponent({ name: 'AnunciosSemLogin' }).props('readOnly')
    ).toBe(true);
  });

  it('keeps the old page when the account flag is off', async () => {
    flags.value = {};
    reply({ configured: false, whatsapp_result: WHATSAPP_RESULT });
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'AnunciosSemLogin' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'MetaAdsHero' }).exists()).toBe(true);
  });

  it('keeps the old page when the server does not enable it', async () => {
    reply({
      configured: false,
      whatsapp_result: { ...WHATSAPP_RESULT, enabled: false },
    });
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'AnunciosSemLogin' }).exists()).toBe(
      false
    );
  });

  it('keeps the old panel for accounts with an active ad account', async () => {
    reply({
      configured: true,
      status: 'active',
      verified_at: '2026-10-01T00:00:00Z',
      ad_account: { id: 'act_1' },
      destinations: { whatsapp: true },
      sales_signal: { enabled: true },
      // Com conexão o servidor nunca liga o painel do WhatsApp (Crm::MetaAds::SemLogin).
      whatsapp_result: { enabled: false },
    });
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'AnunciosSemLogin' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'MetaAdsPanel' }).exists()).toBe(true);
  });

  // Conectado (#2054): o painel usa a largura toda; a lista dos passos fica na aba Conexão.
  const CONNECTED = {
    configured: true,
    status: 'active',
    verified_at: '2026-10-01T00:00:00Z',
    ad_account: { id: 'act_1' },
    destinations: { whatsapp: true },
    sales_signal: { enabled: false },
    whatsapp_result: { enabled: false },
  };

  it('connected, the Result tab has no side list of steps', async () => {
    reply(CONNECTED);
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsPanel' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'MetaAdsChecklist' }).exists()).toBe(
      false
    );
  });

  it('connected, the Connection tab keeps the side list of steps', async () => {
    routing.query = { aba: 'conexao' };
    reply(CONNECTED);
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsSummary' }).exists()).toBe(
      true
    );
    expect(wrapper.findComponent({ name: 'MetaAdsChecklist' }).exists()).toBe(
      true
    );
  });
});
