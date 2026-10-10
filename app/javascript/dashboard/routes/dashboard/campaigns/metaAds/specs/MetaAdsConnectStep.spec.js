import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsConnectStep from '../components/MetaAdsConnectStep.vue';
import { useMetaAdsFacebookLogin } from '../useMetaAdsFacebookLogin';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../useMetaAdsFacebookLogin', () => ({
  useMetaAdsFacebookLogin: vi.fn(),
}));

const FACEBOOK = {
  available: true,
  app_id: '544486745144318',
  configuration_id: '1575134603752871',
  api_version: 'v22.0',
};
const PARTNER = {
  available: true,
  business_id: '555',
  business_name: 'Hub2You',
};

const login = { isConnecting: false, preload: vi.fn(), connect: vi.fn() };

const mountStep = connection =>
  mount(MetaAdsConnectStep, {
    props: { connection },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: { template: '<button><slot /></button>' },
        MetaAdsConnectDialog: { template: '<div />', methods: { open() {} } },
      },
    },
  });

describe('Anúncios da Meta · entrar com o Facebook (#1069)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    login.preload.mockResolvedValue();
    useMetaAdsFacebookLogin.mockReturnValue(login);
  });

  it('com o login configurado, entrar com o Facebook é a ação principal e o compartilhamento fica num link', async () => {
    const wrapper = mountStep({
      facebook_login: FACEBOOK,
      partner: PARTNER,
      whatsapp_portfolio: true,
    });
    await flushPromises();

    expect(wrapper.find('[data-connect-facebook]').exists()).toBe(true);
    expect(wrapper.find('[data-connect-partner]').exists()).toBe(false);
    expect(login.preload).toHaveBeenCalledWith(FACEBOOK);

    await wrapper.find('[data-connect-partner-link]').trigger('click');
    expect(wrapper.find('[data-connect-partner]').exists()).toBe(true);
  });

  it('entrar com o Facebook avisa a página com a conexão gravada', async () => {
    const saved = { configured: true, mode: 'facebook_login' };
    login.connect.mockResolvedValue(saved);
    const wrapper = mountStep({ facebook_login: FACEBOOK });

    await wrapper.find('[data-facebook-login]').trigger('click');
    await flushPromises();

    expect(login.connect).toHaveBeenCalledWith(FACEBOOK);
    expect(wrapper.emitted('facebookLogin')).toEqual([[saved]]);
  });

  it('janela fechada ou popup barrado não grava nada e deixa a dica de liberar o popup', async () => {
    login.connect.mockResolvedValue(null);
    const wrapper = mountStep({ facebook_login: FACEBOOK });

    await wrapper.find('[data-facebook-login]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('facebookLogin')).toBeUndefined();
    expect(wrapper.find('[data-facebook-error]').exists()).toBe(false);
    expect(wrapper.find('[data-facebook-hint]').exists()).toBe(true);
  });

  it('sem compartilhar disponível, o Facebook aparece com um só link de chave e sem aviso âmbar', () => {
    const wrapper = mountStep({
      facebook_login: FACEBOOK,
      partner: { available: false },
      whatsapp_portfolio: false,
    });

    expect(wrapper.find('[data-connect-facebook]').exists()).toBe(true);
    expect(wrapper.findAll('[data-connect-token-link]')).toHaveLength(1);
    expect(wrapper.find('[data-connect-partner-link]').exists()).toBe(false);
    expect(wrapper.find('[data-connect-share-blocked]').exists()).toBe(false);
  });

  it('as frases novas existem em inglês e em português', () => {
    const keys = {
      CONNECT: [
        'FACEBOOK_TITLE',
        'FACEBOOK_BADGE',
        'FACEBOOK_HINT',
        'FACEBOOK_CTA',
        'FACEBOOK_POPUP_HINT',
        'PARTNER_LINK',
      ],
      ACCOUNT: ['VIA_FACEBOOK'],
      SUMMARY: ['MODE_FACEBOOK'],
      ERRORS: [
        'LOGIN_FAILED',
        'LOGIN_UNAVAILABLE',
        'MISSING_ADS_READ',
        'NO_AD_ACCOUNT',
      ],
    };
    [en, ptBR].forEach(catalog => {
      const hub = catalog.CRM_KANBAN.META_ADS_HUB;
      Object.entries(keys).forEach(([section, names]) => {
        names.forEach(name => expect(hub[section][name]).toBeTruthy());
      });
    });
  });

  it('recusa do servidor vira a frase do erro', async () => {
    login.connect.mockRejectedValue({
      response: { data: { error: 'missing_ads_read' } },
    });
    const wrapper = mountStep({ facebook_login: FACEBOOK });

    await wrapper.find('[data-facebook-login]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-facebook-error]').text()).toBe(
      'CRM_KANBAN.META_ADS_HUB.ERRORS.MISSING_ADS_READ'
    );
  });

  it('sem o login configurado, a tela continua como antes', () => {
    const wrapper = mountStep({
      facebook_login: { available: false },
      partner: PARTNER,
      whatsapp_portfolio: true,
    });

    expect(wrapper.find('[data-connect-facebook]').exists()).toBe(false);
    expect(wrapper.find('[data-connect-partner]').exists()).toBe(true);
    expect(login.preload).not.toHaveBeenCalled();
  });
});
