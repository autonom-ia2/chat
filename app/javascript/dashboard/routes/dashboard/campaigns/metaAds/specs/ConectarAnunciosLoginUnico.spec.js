import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConectarAnuncios from '../semLogin/ConectarAnuncios.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { recursosDoLogin } from '../semLogin/loginUnicoRecursos';

// Login único (#2338, flag anuncios_login_unico): depois da conta, o passo "Confira a Página" liga a Página vinda do
// mesmo login (sem o segundo login), e o pronto diz o que já funciona. O Instagram fica num toque à parte.
const facebook = vi.hoisted(() => ({
  connect: vi.fn(),
  preload: vi.fn(() => Promise.resolve()),
}));
const router = vi.hoisted(() => ({ push: vi.fn() }));

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    adAccounts: vi.fn(),
    pixels: vi.fn(),
    select: vi.fn(),
    updateDestinations: vi.fn(),
    sitePages: vi.fn(),
    loginPages: vi.fn(),
    linkPage: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flag === 'anuncios_login_unico',
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '7' } }),
  useRouter: () => router,
}));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { usePermissionGranted: () => computed(() => false) };
});
vi.mock('../useMetaAdsFacebookLogin', async () => {
  const { ref } = await import('vue');
  return {
    useMetaAdsFacebookLogin: () => ({
      isConnecting: ref(false),
      preload: facebook.preload,
      connect: facebook.connect,
    }),
  };
});

const CONNECTION = {
  facebook_login: { available: true, app_id: '1', configuration_id: '2' },
  partner: { business_id: '1455428945005668', business_name: 'Autonom.ia' },
  destinations: { whatsapp: false, site: false },
};
const ACCOUNT = {
  id: 'act_1',
  name: 'Loja Exemplo',
  currency: 'BRL',
  ready: true,
};
const LOJA = {
  id: '104',
  name: 'Loja Exemplo',
  category: 'Loja de roupas',
  followers: 12940,
  instagram: { username: 'lojaexemplo', followers: 4820 },
  linked: false,
};
const BLOG = {
  id: '105',
  name: 'Blog',
  category: 'Blog pessoal',
  followers: 860,
  instagram: null,
  linked: false,
};

const pagesReply = (pages, declined = []) =>
  CrmMetaAdsConnectionAPI.loginPages.mockResolvedValue({
    data: { pages, declined_permissions: declined },
  });

const mountConnect = async () => {
  const wrapper = mount(ConectarAnuncios, {
    props: { connection: CONNECTION },
    global: {
      stubs: {
        Spinner: true,
        MetaTelaGuia: true,
        MetaAdsDestinationsStep: {
          name: 'MetaAdsDestinationsStep',
          props: ['destinations', 'headingLevel'],
          emits: ['saved', 'failed'],
          template: '<div data-destino-stub />',
        },
        MetaAdsSiteLinkDialog: { template: '<div />' },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const toPageStep = async wrapper => {
  await wrapper.find('[data-conectar-facebook]').trigger('click');
  await flushPromises();
  await wrapper.find('[data-conectar-conectar]').trigger('click');
  await flushPromises();
};

const saveDestination = async wrapper => {
  wrapper.findComponent({ name: 'MetaAdsDestinationsStep' }).vm.$emit('saved', {
    destinations: { whatsapp: true, site: false },
    site_pages_count: 0,
  });
  await flushPromises();
};

describe('Anúncios · login único (#2338)', () => {
  const globalPlugins = config.global.plugins;
  beforeAll(() => {
    config.global.plugins = [
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        messages: { en, pt_BR: ptBR },
      }),
    ];
  });
  afterAll(() => {
    config.global.plugins = globalPlugins;
  });
  beforeEach(() => {
    vi.clearAllMocks();
    facebook.connect.mockResolvedValue({ ok: true });
    CrmMetaAdsConnectionAPI.adAccounts.mockResolvedValue({
      data: { ad_accounts: [ACCOUNT] },
    });
    CrmMetaAdsConnectionAPI.pixels.mockResolvedValue({ data: { pixels: [] } });
    CrmMetaAdsConnectionAPI.select.mockResolvedValue({ data: {} });
    CrmMetaAdsConnectionAPI.updateDestinations.mockResolvedValue({ data: {} });
    CrmMetaAdsConnectionAPI.linkPage.mockResolvedValue({
      data: { inbox_id: 9 },
    });
  });

  it('shows five steps and does not promise read-only before signing in', async () => {
    const wrapper = await mountConnect();

    const steps = wrapper.findAll('[data-conectar-como] li');
    expect(steps.map(step => step.text())).toEqual([
      '1Entre com o Facebook',
      '2Confirme a sua conta',
      '3Confira a Página',
      '4Escolha o destino',
      '5Veja seus gastos',
    ]);
    expect(wrapper.text()).toContain('Nada é publicado sem você mandar');
    expect(wrapper.text()).not.toContain('Só vemos os números');
  });

  it('one Page: confirms it, links it without a second login and goes on to the destination', async () => {
    pagesReply([LOJA]);
    const wrapper = await mountConnect();
    await toPageStep(wrapper);

    expect(wrapper.attributes('data-screen')).toBe('page');
    expect(wrapper.find('[data-conectar-pagina]').text()).toContain(
      'Loja Exemplo'
    );
    expect(
      wrapper.find('[data-conectar-faixa] [aria-current="step"]').text()
    ).toContain('Confira a Página');
    expect(wrapper.find('[data-conectar-voltar]').exists()).toBe(false);

    await wrapper.find('[data-conectar-pagina-sim]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.linkPage).toHaveBeenCalledWith('104');
    expect(wrapper.attributes('data-screen')).toBe('destino');
  });

  it('a Page that could not be linked keeps the person on the step with the reason', async () => {
    pagesReply([LOJA]);
    CrmMetaAdsConnectionAPI.linkPage.mockRejectedValue({
      response: { data: { error: 'page_not_granted' } },
    });
    const wrapper = await mountConnect();
    await toPageStep(wrapper);
    await wrapper.find('[data-conectar-pagina-sim]').trigger('click');
    await flushPromises();

    expect(wrapper.attributes('data-screen')).toBe('page');
    expect(wrapper.find('[data-conectar-pagina-erro]').text()).toContain(
      'O Facebook não liberou esta Página'
    );
  });

  it('more than one Page: asks which one and links only that one', async () => {
    pagesReply([LOJA, BLOG]);
    const wrapper = await mountConnect();
    await toPageStep(wrapper);

    expect(wrapper.attributes('data-screen')).toBe('pageChoose');
    expect(
      wrapper.find('[data-conectar-pagina-continuar]').attributes('disabled')
    ).toBeDefined();
    wrapper
      .findComponent('[data-conectar-pagina-escolha]')
      .vm.$emit('update:modelValue', '105');
    await flushPromises();
    await wrapper.find('[data-conectar-pagina-continuar]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.linkPage).toHaveBeenCalledWith('105');
    expect(wrapper.attributes('data-screen')).toBe('destino');
  });

  it('no Page checked: offers to sign in again, or to go on without a Page', async () => {
    pagesReply([]);
    const wrapper = await mountConnect();
    await toPageStep(wrapper);

    expect(wrapper.attributes('data-screen')).toBe('pageNone');
    expect(wrapper.text()).toContain('Faltou marcar a sua Página');

    await wrapper.find('[data-conectar-sem-pagina]').trigger('click');
    await flushPromises();
    expect(CrmMetaAdsConnectionAPI.linkPage).not.toHaveBeenCalled();
    expect(wrapper.attributes('data-screen')).toBe('destino');

    await saveDestination(wrapper);
    const missing = wrapper.find('[data-recurso="CREATE"]');
    expect(missing.attributes('data-falta')).toBe('PAGE');
  });

  it('done lists what works and sends Instagram to its own tap', async () => {
    pagesReply([LOJA], ['read_insights']);
    const wrapper = await mountConnect();
    await toPageStep(wrapper);
    await wrapper.find('[data-conectar-pagina-sim]').trigger('click');
    await flushPromises();
    await saveDestination(wrapper);

    expect(wrapper.attributes('data-screen')).toBe('done');
    const falta = chave =>
      wrapper.find(`[data-recurso="${chave}"]`).attributes('data-falta');
    expect(falta('SPEND')).toBeUndefined();
    expect(falta('COMMENTS_FACEBOOK')).toBeUndefined();
    expect(falta('POSTS')).toBe('PERMISSION');
    expect(falta('MESSAGES_INSTAGRAM')).toBe('INSTAGRAM_TAP');
    expect(wrapper.find('[data-conectar-faltou-permitir]').exists()).toBe(true);

    await wrapper.find('[data-conectar-instagram-ligar]').trigger('click');
    expect(router.push).toHaveBeenCalledWith(
      expect.stringContaining('accounts/7/settings/inboxes/new/instagram')
    );
  });
});

describe('recursosDoLogin', () => {
  it('without a Page, every Page feature says the Page is missing', () => {
    const faltas = recursosDoLogin({ page: null }).map(item => item.falta);
    expect(faltas).toEqual([
      null,
      'PAGE',
      'PAGE',
      'PAGE',
      'PAGE',
      'PAGE',
      'PAGE',
    ]);
  });

  it('leaves out what the login did not ask for, keeps Instagram and flags what was unticked', () => {
    const page = { id: '1', instagram: { username: 'loja' } };
    const itens = recursosDoLogin({
      page,
      granted: ['ads_read', 'ads_management', 'pages_manage_engagement'],
      declined: ['read_insights'],
    });
    expect(itens).toEqual([
      { chave: 'SPEND', falta: null },
      { chave: 'CREATE', falta: null },
      { chave: 'COMMENTS_FACEBOOK', falta: null },
      { chave: 'POSTS', falta: 'PERMISSION' },
      { chave: 'COMMENTS_INSTAGRAM', falta: 'INSTAGRAM_TAP' },
      { chave: 'MESSAGES_INSTAGRAM', falta: 'INSTAGRAM_TAP' },
    ]);
  });

  it('a Page without Instagram says Instagram is missing, not a tap away', () => {
    const page = { id: '1', instagram: null };
    const instagram = recursosDoLogin({ page }).filter(item =>
      item.chave.endsWith('INSTAGRAM')
    );
    expect(instagram.map(item => item.falta)).toEqual([
      'INSTAGRAM',
      'INSTAGRAM',
    ]);
  });
});
