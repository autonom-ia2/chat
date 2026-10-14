import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsConnectStep from '../components/MetaAdsConnectStep.vue';
import MetaAdsFacebookLoginCard from '../components/MetaAdsFacebookLoginCard.vue';
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
  configuration_id: '1533640672115651',
  api_version: 'v22.0',
};
const PARTNER = {
  available: true,
  business_id: '555',
  business_name: 'Hub2You',
};

const login = {
  isConnecting: ref(false),
  preload: vi.fn(),
  connect: vi.fn(),
};

const mocks = { $t: key => key };
const stubs = {
  Button: { template: '<button><slot /></button>' },
  MetaAdsConnectDialog: { template: '<div />', methods: { open() {} } },
};

const mountStep = connection =>
  mount(MetaAdsConnectStep, {
    props: { connection },
    global: { mocks, stubs },
  });

const mountCard = (props = {}) =>
  mount(MetaAdsFacebookLoginCard, {
    props: { config: FACEBOOK, ...props },
    global: { mocks },
  });

const clickSignIn = async wrapper => {
  await wrapper.find('[data-facebook-login]').trigger('click');
  await flushPromises();
};

const CARD_KEYS = [
  'TITLE',
  'LEAD',
  'HOW_LABEL',
  'HOW_1_TITLE',
  'HOW_1_TEXT',
  'HOW_2_TITLE',
  'HOW_2_TEXT',
  'HOW_3_TITLE',
  'HOW_3_TEXT',
  'CTA',
  'WAITING',
  'TRUST_PASSWORD',
  'TRUST_ADS',
  'TRUST_OFF',
  'OTHER_WAYS',
  'PARTNER_TITLE',
  'PARTNER_TEXT',
  'PARTNER_CTA',
  'TOKEN_TITLE',
  'TOKEN_TEXT',
  'TOKEN_CTA',
  'POPUP_TITLE',
  'POPUP_TEXT',
  'POPUP_STEP_1',
  'POPUP_STEP_2',
  'POPUP_STEP_3',
  'NO_AD_ACCOUNT_TITLE',
  'NO_ACCESS_TITLE',
  'RETRY',
  'BACK',
];
const ERROR_KEYS = [
  'LOGIN_FAILED',
  'LOGIN_UNAVAILABLE',
  'MISSING_ADS_READ',
  'NO_AD_ACCOUNT',
];

describe('Anúncios da Meta · passo 1 com o Facebook (#1069)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    login.preload.mockResolvedValue();
    login.isConnecting.value = false;
    useMetaAdsFacebookLogin.mockReturnValue(login);
  });

  describe('o passo', () => {
    it('com o login configurado, o passo inteiro é entrar com o Facebook', async () => {
      const wrapper = mountStep({
        facebook_login: FACEBOOK,
        partner: PARTNER,
        whatsapp_portfolio: true,
      });
      await flushPromises();

      expect(wrapper.find('[data-connect-facebook]').exists()).toBe(true);
      expect(wrapper.find('[data-connect-partner]').exists()).toBe(false);
      expect(login.preload).toHaveBeenCalledWith(FACEBOOK);
    });

    it('compartilhar abre pelo outro jeito de conectar e tem como voltar', async () => {
      const wrapper = mountStep({
        facebook_login: FACEBOOK,
        partner: PARTNER,
        whatsapp_portfolio: true,
      });

      await wrapper.find('[data-facebook-other]').trigger('click');
      await wrapper
        .find('[data-facebook-other-partner] button')
        .trigger('click');
      expect(wrapper.find('[data-connect-partner]').exists()).toBe(true);
      expect(wrapper.find('[data-connect-facebook]').exists()).toBe(false);

      await wrapper.find('[data-facebook-back]').trigger('click');
      expect(wrapper.find('[data-connect-facebook]').exists()).toBe(true);
    });

    it('avisa a página com a conexão gravada', async () => {
      const saved = { configured: true, mode: 'facebook_login' };
      login.connect.mockResolvedValue(saved);
      const wrapper = mountStep({ facebook_login: FACEBOOK });

      await clickSignIn(wrapper);

      expect(wrapper.emitted('facebookLogin')).toEqual([[saved]]);
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

  describe('o cartão', () => {
    it('mostra os três passos com o pedido de deixar tudo marcado no meio', () => {
      const wrapper = mountCard();

      expect(wrapper.findAll('[data-facebook-how]')).toHaveLength(3);
      expect(wrapper.find('[data-facebook-how="2"]').text()).toContain(
        'CRM_KANBAN.META_ADS_HUB.CONNECT.FACEBOOK.HOW_2_TITLE'
      );
    });

    it('enquanto a janela está aberta, lembra de deixar tudo marcado', () => {
      useMetaAdsFacebookLogin.mockReturnValue({
        ...login,
        isConnecting: ref(true),
      });
      const wrapper = mountCard();

      expect(wrapper.find('[data-facebook-waiting]').exists()).toBe(true);
      expect(wrapper.find('[data-facebook-other]').exists()).toBe(false);
      expect(
        wrapper.find('[data-facebook-login]').attributes('disabled')
      ).toBeDefined();
    });

    it('janela fechada ou barrada explica como liberar e troca o botão para entrar de novo', async () => {
      login.connect.mockResolvedValue(null);
      const wrapper = mountCard();

      await clickSignIn(wrapper);

      expect(wrapper.emitted('connected')).toBeUndefined();
      expect(wrapper.findAll('[data-facebook-hint] li')).toHaveLength(3);
      expect(wrapper.find('[data-facebook-login]').text()).toContain(
        'CRM_KANBAN.META_ADS_HUB.CONNECT.FACEBOOK.RETRY'
      );
    });

    it('conta de anúncios não marcada vira aviso com título e frase', async () => {
      login.connect.mockRejectedValue({
        response: { data: { error: 'no_ad_account' } },
      });
      const wrapper = mountCard();

      await clickSignIn(wrapper);

      const alert = wrapper.find('[data-facebook-error]');
      expect(alert.text()).toContain(
        'CRM_KANBAN.META_ADS_HUB.CONNECT.FACEBOOK.NO_AD_ACCOUNT_TITLE'
      );
      expect(alert.text()).toContain(
        'CRM_KANBAN.META_ADS_HUB.ERRORS.NO_AD_ACCOUNT'
      );
    });

    it('a Meta fora do ar vira aviso vermelho e o clique seguinte limpa o aviso', async () => {
      login.connect.mockRejectedValueOnce({
        response: { data: { error: 'meta_unavailable' } },
      });
      const saved = { configured: true, mode: 'facebook_login' };
      login.connect.mockResolvedValueOnce(saved);
      const wrapper = mountCard();

      await clickSignIn(wrapper);
      expect(wrapper.find('[data-facebook-error]').classes()).toContain(
        'bg-n-ruby-2'
      );

      await clickSignIn(wrapper);
      expect(wrapper.find('[data-facebook-error]').exists()).toBe(false);
      expect(wrapper.emitted('connected')).toEqual([[saved]]);
    });

    it('sem compartilhar disponível, o outro jeito oferece só a chave', async () => {
      const wrapper = mountCard({ canShare: false });

      await wrapper.find('[data-facebook-other]').trigger('click');

      expect(wrapper.find('[data-facebook-other-partner]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-facebook-other-token]').exists()).toBe(true);
      await wrapper.find('[data-connect-token-link]').trigger('click');
      expect(wrapper.emitted('token')).toHaveLength(1);
    });
  });

  it('as frases do cartão existem em inglês e em português', () => {
    [en, ptBR].forEach(catalog => {
      const hub = catalog.CRM_KANBAN.META_ADS_HUB;
      CARD_KEYS.forEach(key => expect(hub.CONNECT.FACEBOOK[key]).toBeTruthy());
      ERROR_KEYS.forEach(key => expect(hub.ERRORS[key]).toBeTruthy());
      expect(hub.ACCOUNT.VIA_FACEBOOK).toBeTruthy();
      expect(hub.SUMMARY.MODE_FACEBOOK).toBeTruthy();
    });
  });
});
