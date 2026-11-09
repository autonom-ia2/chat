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
// #2406: as flags ligadas na conta; instagram_login_unico entra só nos testes do Instagram pela Página.
const flags = vi.hoisted(() => new Set(['anuncios_login_unico']));

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    adAccounts: vi.fn(),
    pixels: vi.fn(),
    select: vi.fn(),
    updateDestinations: vi.fn(),
    sitePages: vi.fn(),
    loginPages: vi.fn(),
    linkPage: vi.fn(),
    linkInstagram: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.has(flag),
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
    flags.clear();
    flags.add('anuncios_login_unico');
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

  it('a Page whose inbox would lose its messages keeps the inbox and asks to sign in again', async () => {
    pagesReply([{ ...LOJA, linked: true }]);
    CrmMetaAdsConnectionAPI.linkPage.mockRejectedValue({
      response: { status: 422, data: { error: 'missing_permissions' } },
    });
    const wrapper = await mountConnect();
    await toPageStep(wrapper);
    await wrapper.find('[data-conectar-pagina-sim]').trigger('click');
    await flushPromises();

    expect(wrapper.attributes('data-screen')).toBe('page');
    expect(wrapper.find('[data-conectar-pagina-erro]').text()).toContain(
      'Faltou permitir'
    );
    facebook.connect.mockClear();
    await wrapper.find('[data-conectar-pagina-permitir]').trigger('click');
    await flushPromises();
    expect(facebook.connect).toHaveBeenCalled();
  });

  it('inbox limit of the plan says so, instead of asking to try again later', async () => {
    pagesReply([LOJA]);
    CrmMetaAdsConnectionAPI.linkPage.mockRejectedValue({
      response: { status: 402, data: { message: 'Account limit exceeded' } },
    });
    const wrapper = await mountConnect();
    await toPageStep(wrapper);
    await wrapper.find('[data-conectar-pagina-sim]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-conectar-pagina-erro]').text()).toContain(
      'limite de caixas de entrada'
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

  const toDone = async () => {
    pagesReply([LOJA]);
    const wrapper = await mountConnect();
    await toPageStep(wrapper);
    await wrapper.find('[data-conectar-pagina-sim]').trigger('click');
    await flushPromises();
    await saveDestination(wrapper);
    return wrapper;
  };

  // #2406: com a flag do Instagram, o toque liga o Instagram da Página aqui mesmo, com o mesmo login.
  it('with Instagram by the Page: the tap links Instagram here, without the Instagram login', async () => {
    flags.add('instagram_login_unico');
    CrmMetaAdsConnectionAPI.linkInstagram.mockResolvedValue({
      data: { inbox_id: 11, name: 'lojaexemplo' },
    });
    const wrapper = await toDone();

    expect(wrapper.find('[data-conectar-ligar-instagram]').text()).toContain(
      'Ligue o @lojaexemplo com este mesmo login do Facebook'
    );
    await wrapper.find('[data-conectar-instagram-ligar]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.linkInstagram).toHaveBeenCalledWith('104');
    expect(router.push).not.toHaveBeenCalled();
    expect(
      wrapper
        .find('[data-recurso="MESSAGES_INSTAGRAM"]')
        .attributes('data-falta')
    ).toBeUndefined();
    expect(wrapper.find('[data-conectar-ligar-instagram]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-conectar-instagram-ligado]').text()).toBe(
      'O @lojaexemplo está ligado. O Direct e os comentários chegam aqui.'
    );
  });

  it('with Instagram by the Page: Instagram left unchecked says to sign in again, and the tap stays', async () => {
    flags.add('instagram_login_unico');
    CrmMetaAdsConnectionAPI.linkInstagram.mockRejectedValue({
      response: { status: 422, data: { error: 'missing_permissions' } },
    });
    const wrapper = await toDone();

    await wrapper.find('[data-conectar-instagram-ligar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-conectar-instagram-erro]').text()).toBe(
      'O Instagram ficou desmarcado na janela do Facebook. Entre de novo e deixe o Instagram marcado.'
    );
    expect(
      wrapper.find('[data-conectar-instagram-ligar]').attributes('disabled')
    ).toBeUndefined();
    expect(wrapper.find('[data-conectar-instagram-ligado]').exists()).toBe(
      false
    );
    expect(
      wrapper
        .find('[data-recurso="MESSAGES_INSTAGRAM"]')
        .attributes('data-falta')
    ).toBe('INSTAGRAM_TAP');
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

  it('Instagram by the Page: already linked counts like the Page features', () => {
    const page = { id: '1', instagram: { username: 'loja', linked: true } };
    const instagram = recursosDoLogin({
      page,
      declined: ['instagram_manage_comments'],
      pelaPagina: true,
    }).filter(item => item.chave.endsWith('INSTAGRAM'));
    expect(instagram).toEqual([
      { chave: 'COMMENTS_INSTAGRAM', falta: 'PERMISSION' },
      { chave: 'MESSAGES_INSTAGRAM', falta: null },
    ]);
    const semFlag = recursosDoLogin({ page }).filter(item =>
      item.chave.endsWith('INSTAGRAM')
    );
    expect(semFlag.map(item => item.falta)).toEqual([
      'INSTAGRAM_TAP',
      'INSTAGRAM_TAP',
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
