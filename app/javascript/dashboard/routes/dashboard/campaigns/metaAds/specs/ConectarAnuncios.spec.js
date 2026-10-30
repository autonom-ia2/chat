import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConectarAnuncios from '../semLogin/ConectarAnuncios.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Conectar a conta de anúncios a partir do painel sem login (#2054): uma ação por tela, Facebook primeiro,
// compartilhamento como parceiro para quem precisa.
const facebook = vi.hoisted(() => ({
  connect: vi.fn(),
  preload: vi.fn(() => Promise.resolve()),
}));

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    adAccounts: vi.fn(),
    pixels: vi.fn(),
    select: vi.fn(),
    updateDestinations: vi.fn(),
  },
}));
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
  client_portfolio_id: null,
  destinations: { whatsapp: false, site: false },
};
const ACCOUNT = {
  id: 'act_1',
  name: 'Onze Onze — Anúncios',
  currency: 'BRL',
  ready: true,
  spend_30d: 3420.5,
  recommended: true,
};
const OTHER = {
  id: 'act_2',
  name: 'Onze Onze — Institucional',
  currency: 'BRL',
  ready: true,
  spend_30d: 210,
  recommended: false,
};

const SEGUROS = {
  id: '2164882667623689',
  name: 'Pixel Placement Seguros',
  last_fired_time: '2026-10-22T10:00:00+0000',
};
const MEDICO = {
  id: '1674865833738871',
  name: 'Pixel Placement - RC Médico',
  last_fired_time: '2026-10-27T10:00:00+0000',
};

const pixelsReply = rows =>
  CrmMetaAdsConnectionAPI.pixels.mockResolvedValue({
    data: { pixels: rows },
  });

const accountsReply = rows =>
  CrmMetaAdsConnectionAPI.adAccounts.mockResolvedValue({
    data: { ad_accounts: rows },
  });

const mountConnect = async props => {
  const wrapper = mount(ConectarAnuncios, {
    props: { connection: CONNECTION, ...props },
    global: {
      stubs: {
        Spinner: true,
        MetaTelaGuia: true,
        MetaAdsDestinationsStep: {
          name: 'MetaAdsDestinationsStep',
          props: ['destinations'],
          emits: ['saved'],
          template: '<div data-destino-stub />',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

// Passo 3 (#2338): o destino é gravado pelo próprio passo de destinos, que avisa "saved".
const saveDestination = async wrapper => {
  wrapper.findComponent({ name: 'MetaAdsDestinationsStep' }).vm.$emit('saved');
  await flushPromises();
};

describe('Anúncios sem login · conectar a conta de anúncios (#2054)', () => {
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
    CrmMetaAdsConnectionAPI.select.mockResolvedValue({ data: {} });
    pixelsReply([]);
    CrmMetaAdsConnectionAPI.updateDestinations.mockResolvedValue({ data: {} });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('with Facebook: signs in, finds the only account, connects it, asks where the ads lead and goes to the panel (no Pixel: asks nothing)', async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT]);
    const wrapper = await mountConnect();

    expect(wrapper.attributes('data-screen')).toBe('start');
    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.adAccounts).toHaveBeenCalledWith(
      'facebook_login'
    );
    expect(wrapper.attributes('data-screen')).toBe('found');
    expect(wrapper.find('[data-conectar-conta]').text()).toContain(
      'Onze Onze — Anúncios'
    );

    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith({
      mode: 'facebook_login',
      adAccountId: 'act_1',
      pixelId: null,
      noSite: false,
    });
    expect(wrapper.find('[data-conectar-pixel-pergunta]').exists()).toBe(false);
    // Passo 3: conta sem destino nenhum ganha o WhatsApp (quem sai aqui fica como antes) e a pessoa escolhe.
    expect(wrapper.attributes('data-screen')).toBe('destino');
    expect(CrmMetaAdsConnectionAPI.updateDestinations).toHaveBeenCalledTimes(1);
    expect(CrmMetaAdsConnectionAPI.updateDestinations).toHaveBeenCalledWith({
      whatsapp: true,
      site: false,
    });
    expect(
      wrapper
        .findComponent({ name: 'MetaAdsDestinationsStep' })
        .props('destinations')
    ).toEqual({ whatsapp: true, site: false });
    expect(
      wrapper.find('[data-conectar-faixa] [aria-current="step"]').text()
    ).toContain('Escolha o destino');
    expect(wrapper.find('[data-conectar-voltar]').exists()).toBe(false);

    await saveDestination(wrapper);
    expect(wrapper.attributes('data-screen')).toBe('done');
    expect(
      wrapper.find('[data-conectar-faixa] [aria-current="step"]').text()
    ).toContain('Veja seus gastos');

    await wrapper.find('[data-conectar-ver-painel]').trigger('click');
    expect(wrapper.emitted('connected')).toHaveLength(1);
  });

  it('with more than one account, the person chooses; the most used one is marked', async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT, OTHER, { ...OTHER, id: 'act_3', ready: false }]);
    const wrapper = await mountConnect();

    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();

    expect(wrapper.attributes('data-screen')).toBe('choose');
    expect(wrapper.find('[data-conectar-escolher="act_3"]').exists()).toBe(
      false
    );
    expect(
      wrapper
        .find('[data-conectar-escolher="act_1"] [data-conectar-mais-usada]')
        .exists()
    ).toBe(true);
    expect(
      wrapper
        .find('[data-conectar-escolher="act_2"] [data-conectar-mais-usada]')
        .exists()
    ).toBe(false);

    await wrapper.find('[data-conectar-escolher="act_2"]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith(
      expect.objectContaining({ adAccountId: 'act_2' })
    );
  });

  // A Meta não diz qual Pixel a pessoa marcou na janela do Facebook (#2343): com mais de um, a tela pergunta.
  const connectWithTwo = async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT]);
    pixelsReply([SEGUROS, MEDICO]);
    const wrapper = await mountConnect();
    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();
    return wrapper;
  };

  const answer = async (wrapper, value) => {
    await wrapper
      .find(`[role="option"][data-value="${value}"]`)
      .trigger('click');
    await wrapper.find('[data-conectar-pixel-continuar]').trigger('click');
    await flushPromises();
  };
  const answerAndSave = async (wrapper, value) => {
    await answer(wrapper, value);
    expect(wrapper.attributes('data-screen')).toBe('destino');
    await saveDestination(wrapper);
  };

  it('with more than one Pixel, asks which one before saving anything', async () => {
    const wrapper = await connectWithTwo();

    expect(CrmMetaAdsConnectionAPI.pixels).toHaveBeenCalledWith(
      'facebook_login',
      'act_1'
    );
    expect(wrapper.attributes('data-screen')).toBe('pixel');
    expect(CrmMetaAdsConnectionAPI.select).not.toHaveBeenCalled();
    expect(wrapper.find('[role="combobox"]').exists()).toBe(true);
    expect(wrapper.find('select').exists()).toBe(false);
    expect(
      wrapper.find('[data-conectar-pixel-continuar]').attributes('disabled')
    ).toBeDefined();

    // O mais antigo, de propósito: nada escolhe pelo disparo mais recente.
    await answerAndSave(wrapper, SEGUROS.id);

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledTimes(1);
    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith({
      mode: 'facebook_login',
      adAccountId: 'act_1',
      pixelId: SEGUROS.id,
      noSite: false,
    });
    expect(wrapper.attributes('data-screen')).toBe('done');
    expect(wrapper.find('[data-conectar-pixel]').text()).toContain(
      'Pixel Placement Seguros'
    );
    expect(wrapper.find('[data-conectar-pixel-alterar]').exists()).toBe(true);
  });

  it('with more than one Pixel, "I have no website" saves no Pixel on purpose', async () => {
    const wrapper = await connectWithTwo();

    await answerAndSave(wrapper, 'none');

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith({
      mode: 'facebook_login',
      adAccountId: 'act_1',
      pixelId: null,
      noSite: true,
    });
    expect(wrapper.find('[data-conectar-pixel]').text()).toContain(
      'sem código do site'
    );
  });

  it('a failed save after the question goes to the error screen', async () => {
    const wrapper = await connectWithTwo();
    CrmMetaAdsConnectionAPI.select.mockRejectedValue({
      response: { data: { error: 'pixel_not_found' } },
    });

    await answer(wrapper, MEDICO.id);

    expect(wrapper.attributes('data-screen')).toBe('notyet');
    expect(CrmMetaAdsConnectionAPI.updateDestinations).not.toHaveBeenCalled();
  });

  const connectAndChange = async () => {
    const wrapper = await connectWithTwo();
    await answerAndSave(wrapper, MEDICO.id);
    await wrapper.find('[data-conectar-pixel-alterar]').trigger('click');
    return wrapper;
  };

  it('"Change" in done saves another Pixel', async () => {
    const wrapper = await connectAndChange();

    expect(
      wrapper.find('[data-conectar-pixel] [role="combobox"]').exists()
    ).toBe(true);
    await wrapper
      .find(`[data-conectar-pixel] [role="option"][data-value="${SEGUROS.id}"]`)
      .trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenLastCalledWith({
      mode: 'facebook_login',
      adAccountId: 'act_1',
      pixelId: SEGUROS.id,
      noSite: false,
    });
    expect(wrapper.find('[data-conectar-pixel]').text()).toContain(
      'Pixel Placement Seguros'
    );
  });

  it('"Change" to "I have no website" saves no Pixel on purpose', async () => {
    const wrapper = await connectAndChange();

    await wrapper
      .find('[data-conectar-pixel] [role="option"][data-value="none"]')
      .trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenLastCalledWith({
      mode: 'facebook_login',
      adAccountId: 'act_1',
      pixelId: null,
      noSite: true,
    });
  });

  it('"Cancel" closes the change without saving', async () => {
    const wrapper = await connectAndChange();

    await wrapper.find('[data-conectar-pixel-cancelar]').trigger('click');

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-conectar-pixel-alterar]').exists()).toBe(true);
  });

  it('a failed change says why and keeps the choice open', async () => {
    const wrapper = await connectAndChange();
    CrmMetaAdsConnectionAPI.select.mockRejectedValue({
      response: { data: { error: 'pixel_not_found' } },
    });

    await wrapper
      .find(`[data-conectar-pixel] [role="option"][data-value="${SEGUROS.id}"]`)
      .trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-conectar-pixel-erro]').text()).not.toBe('');
    expect(wrapper.find('[data-conectar-pixel-cancelar]').exists()).toBe(true);
  });

  it('a single Pixel is saved by itself, with nothing to ask or change', async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT]);
    pixelsReply([SEGUROS]);
    const wrapper = await mountConnect();

    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-conectar-pixel-pergunta]').exists()).toBe(false);
    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith({
      mode: 'facebook_login',
      adAccountId: 'act_1',
      pixelId: SEGUROS.id,
      noSite: false,
    });
    expect(wrapper.find('[data-conectar-pixel-alterar]').exists()).toBe(false);
  });

  it('without the Pixel list the account still connects, and "done" says where to choose the code', async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT]);
    CrmMetaAdsConnectionAPI.pixels.mockRejectedValue(new Error());
    const wrapper = await mountConnect();

    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith(
      expect.objectContaining({ pixelId: null })
    );
    await saveDestination(wrapper);
    expect(wrapper.attributes('data-screen')).toBe('done');
    expect(wrapper.find('[data-conectar-pixel-falhou]').exists()).toBe(true);
  });

  it('closing the Facebook window keeps the start screen with a notice and asks nothing', async () => {
    facebook.connect.mockResolvedValue(null);
    const wrapper = await mountConnect();

    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();

    expect(wrapper.attributes('data-screen')).toBe('start');
    const notice = wrapper.find('[data-conectar-aviso-login]').text();
    expect(notice).toContain('fechou antes do fim');
    expect(notice).not.toContain('não abriu');
    expect(CrmMetaAdsConnectionAPI.adAccounts).not.toHaveBeenCalled();
  });

  it('a failed connection says why and offers to check again', async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT]);
    CrmMetaAdsConnectionAPI.select.mockRejectedValue({
      response: { data: { error: 'missing_ads_read' } },
    });
    const wrapper = await mountConnect();

    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();

    expect(wrapper.attributes('data-screen')).toBe('notyet');
    expect(wrapper.find('[data-conectar-motivo]').text()).not.toBe('');
    expect(wrapper.find('[data-conectar-de-novo]').exists()).toBe(true);
  });

  it('an account that already chose its destination keeps it, with nothing saved before step 3', async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT]);
    const wrapper = await mountConnect({
      connection: {
        ...CONNECTION,
        destinations: { whatsapp: true, site: true },
      },
    });

    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();

    expect(
      wrapper
        .findComponent({ name: 'MetaAdsDestinationsStep' })
        .props('destinations')
    ).toEqual({ whatsapp: true, site: true });
    expect(CrmMetaAdsConnectionAPI.updateDestinations).not.toHaveBeenCalled();
  });

  it('sharing as partner also goes through step 3', async () => {
    accountsReply([ACCOUNT]);
    const wrapper = await mountConnect({
      connection: { ...CONNECTION, facebook_login: { available: false } },
    });

    await wrapper.find('[data-conectar-copiar]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-abrir-meta]').trigger('click');
    await wrapper.find('[data-conectar-liberei]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith(
      expect.objectContaining({ mode: 'partner' })
    );
    expect(wrapper.attributes('data-screen')).toBe('destino');
    await saveDestination(wrapper);
    expect(wrapper.attributes('data-screen')).toBe('done');
  });

  it('on step 3 the focus goes to the question, for screen readers', async () => {
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([ACCOUNT]);
    const wrapper = mount(ConectarAnuncios, {
      props: { connection: CONNECTION },
      attachTo: document.body,
      global: {
        stubs: {
          Spinner: true,
          MetaTelaGuia: true,
          MetaAdsDestinationsStep: {
            name: 'MetaAdsDestinationsStep',
            props: ['destinations'],
            template:
              '<section data-meta-ads-destinations><h3>Para onde?</h3></section>',
          },
        },
      },
    });
    await flushPromises();
    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conectar-conectar]').trigger('click');
    await flushPromises();

    expect(document.activeElement?.textContent).toBe('Para onde?');
    wrapper.unmount();
  });

  it('shows the four steps before signing in', async () => {
    const wrapper = await mountConnect();

    expect(wrapper.text()).toContain('Escolha o destino');
    expect(
      wrapper.findAll('[data-conectar-como] > li').map(item => item.text())
    ).toEqual([
      '1Entre com o Facebook',
      '2Confirme a sua conta',
      '3Escolha o destino',
      '4Veja seus gastos',
    ]);
  });

  it('sharing as partner: copy, open Meta, mark, and it checks again by itself while it has not arrived', async () => {
    vi.useFakeTimers();
    accountsReply([]);
    const wrapper = await mountConnect({
      connection: { ...CONNECTION, facebook_login: { available: false } },
    });
    Object.assign(navigator, {
      clipboard: { writeText: vi.fn(() => Promise.resolve()) },
    });
    vi.spyOn(window, 'open').mockReturnValue(null);

    expect(wrapper.attributes('data-screen')).toBe('copy');
    await wrapper.find('[data-conectar-copiar]').trigger('click');
    await flushPromises();
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
      '1455428945005668'
    );
    expect(wrapper.attributes('data-screen')).toBe('meta');

    await wrapper.find('[data-conectar-abrir-meta]').trigger('click');
    expect(window.open).toHaveBeenCalled();
    await wrapper.find('[data-conectar-liberei]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.adAccounts).toHaveBeenCalledWith('partner');
    expect(wrapper.attributes('data-screen')).toBe('notyet');

    accountsReply([ACCOUNT]);
    await vi.advanceTimersByTimeAsync(20_000);
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.adAccounts).toHaveBeenCalledTimes(2);
    expect(wrapper.attributes('data-screen')).toBe('found');
  });

  it('Facebook with no account does not keep checking by itself', async () => {
    vi.useFakeTimers();
    facebook.connect.mockResolvedValue({ ok: true });
    accountsReply([]);
    const wrapper = await mountConnect();

    await wrapper.find('[data-conectar-facebook]').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(60_000);

    expect(wrapper.attributes('data-screen')).toBe('notyet');
    expect(CrmMetaAdsConnectionAPI.adAccounts).toHaveBeenCalledTimes(1);
  });

  it('resumes on the account check when the connection stopped in the middle (choosing)', async () => {
    accountsReply([ACCOUNT]);
    const wrapper = await mountConnect({
      resume: { state: 'choosing', mode: 'facebook_login' },
    });

    expect(CrmMetaAdsConnectionAPI.adAccounts).toHaveBeenCalledWith(
      'facebook_login'
    );
    expect(wrapper.attributes('data-screen')).toBe('found');
  });

  it('a connection that fell starts from the beginning with the warning (broken)', async () => {
    const wrapper = await mountConnect({
      resume: { state: 'broken', mode: 'facebook_login' },
    });

    expect(wrapper.attributes('data-screen')).toBe('start');
    expect(wrapper.find('[data-conectar-caiu]').exists()).toBe(true);
    expect(CrmMetaAdsConnectionAPI.adAccounts).not.toHaveBeenCalled();
  });
});
