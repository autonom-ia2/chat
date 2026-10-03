import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import instagramClient from 'dashboard/api/channel/instagramClient';
import TesterOnboarding from './TesterOnboarding.vue';
import Instagram from '../Instagram.vue';

vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: {
    getTesterConfiguration: vi.fn(),
    searchTesters: vi.fn(),
    getTesterStatus: vi.fn(),
    inviteTester: vi.fn(),
    generateAuthorization: vi.fn(),
  },
}));
const accountId = ref(17);
const disabled = ref(false);
const config = ref({ instagramTesterAutomationEnabled: false });
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId, isMetaInboxCreationDisabled: disabled }),
}));
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => config }));
const i18n = withFullI18n('pt_BR');
enableAutoUnmount(afterEach);
const candidate = {
  id: '10001',
  username: 'demo_company',
  name: 'Empresa Demo',
  avatar_url: null,
  selection_token: 'signed-demo-selection',
};
const configuration = {
  enabled: true,
  available: true,
  app_name: 'Aplicativo Demo',
  acceptance_url: 'https://www.instagram.com/accounts/manage_access/',
};
const mountOptions = {
  global: {
    directives: { 'dompurify-html': () => {} },
    stubs: { RouterLink: { template: '<a><slot /></a>' } },
  },
};
const mountTester = () =>
  mount(TesterOnboarding, { ...mountOptions, props: { accountId: 17 } });
const button = (wrapper, text) =>
  wrapper.findAll('button').find(item => item.text() === text);
const searchAndSelect = async wrapper => {
  await flushPromises();
  await wrapper.find('input').setValue('@demo_company');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  await wrapper
    .find('[aria-label="Selecionar @demo_company, Empresa Demo"]')
    .trigger('click');
  await flushPromises();
};

beforeEach(() => {
  i18n.global.locale.value = 'pt_BR';
  accountId.value = 17;
  disabled.value = false;
  config.value = { instagramTesterAutomationEnabled: false };
  instagramClient.getTesterConfiguration.mockResolvedValue({
    data: configuration,
  });
  instagramClient.searchTesters.mockResolvedValue({
    data: { results: [candidate] },
  });
  instagramClient.getTesterStatus.mockResolvedValue({
    data: { status: 'pending' },
  });
});

describe('Instagram assisted tester onboarding', () => {
  it('keeps the legacy branch and makes no tester requests with the flag off', async () => {
    const wrapper = mount(Instagram, mountOptions);
    await flushPromises();
    expect(wrapper.text()).toContain('Continuar com o Instagram');
    expect(wrapper.find('input').exists()).toBe(false);
    expect(instagramClient.getTesterConfiguration).not.toHaveBeenCalled();
    expect(instagramClient.searchTesters).not.toHaveBeenCalled();
    expect(instagramClient.getTesterStatus).not.toHaveBeenCalled();
    expect(instagramClient.inviteTester).not.toHaveBeenCalled();
  });

  it('keeps the classic OAuth click payload unchanged with feature off', async () => {
    instagramClient.generateAuthorization.mockResolvedValue({
      data: { url: window.location.href },
    });
    const wrapper = mount(Instagram, mountOptions);
    await flushPromises();
    await button(wrapper, 'Continuar com o Instagram').trigger('click');
    await flushPromises();
    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith();
    expect(instagramClient.getTesterConfiguration).not.toHaveBeenCalled();
  });

  it('falls back to legacy only when this account is explicitly disabled', async () => {
    config.value.instagramTesterAutomationEnabled = true;
    instagramClient.getTesterConfiguration.mockResolvedValue({
      data: { enabled: false },
    });
    const wrapper = mount(Instagram, mountOptions);
    await flushPromises();
    expect(wrapper.findComponent(TesterOnboarding).exists()).toBe(false);
    expect(wrapper.text()).toContain('Continuar com o Instagram');
  });

  it.each([
    { ...configuration, available: false },
    { ...configuration, app_name: null },
  ])('fails closed for unavailable configuration %j', async data => {
    instagramClient.getTesterConfiguration.mockResolvedValue({ data });
    const wrapper = mountTester();
    await flushPromises();
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.text()).toContain('Procure o suporte');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(button(wrapper, 'Continuar com o Instagram')).toBeUndefined();
  });

  it('requires explicit selection even with a single search result', async () => {
    const wrapper = mountTester();
    await flushPromises();
    await wrapper.find('input').setValue(' @Demo_Company ');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(instagramClient.searchTesters).toHaveBeenCalledWith(
      'demo_company',
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(wrapper.text()).toContain('@demo_company');
    expect(instagramClient.getTesterStatus).not.toHaveBeenCalled();
    expect(instagramClient.inviteTester).not.toHaveBeenCalled();
  });

  it('shows accessible computer instructions, exact account, app, and safe direct link for PENDING', async () => {
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    expect(wrapper.findAll('ol li')).toHaveLength(4);
    expect(wrapper.text()).toContain('No navegador de um computador');
    expect(wrapper.text()).toContain('Apps e sites → Convites do testador');
    expect(wrapper.text()).toContain(
      'Localize Aplicativo Demo e clique em Aceitar'
    );
    expect(wrapper.text()).toContain('@demo_company');
    const link = wrapper.find(
      'a[href="https://www.instagram.com/accounts/manage_access/"]'
    );
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.attributes('target')).toBe('_blank');
    expect(button(wrapper, 'Já aceitei — verificar')).toBeDefined();
    expect(wrapper.find('[aria-live="polite"]').exists()).toBe(true);
    expect(instagramClient.inviteTester).not.toHaveBeenCalled();
    expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
    await link.trigger('click');
    expect(button(wrapper, 'Continuar com o Instagram')).toBeUndefined();
  });

  it('announces still pending without resending or starting OAuth', async () => {
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    await button(wrapper, 'Já aceitei — verificar').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('O convite ainda aparece como pendente');
    expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
    expect(instagramClient.inviteTester).not.toHaveBeenCalled();
  });

  it('CONFIRMED exposes only invitation acceptance and requires a separate OAuth click with token', async () => {
    instagramClient.getTesterStatus.mockResolvedValue({
      data: { status: 'accepted' },
    });
    instagramClient.generateAuthorization.mockRejectedValue(
      new Error('network')
    );
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    expect(wrapper.text()).toContain('Convite aceito');
    expect(wrapper.text()).toContain('Falta autorizar a conexão');
    expect(wrapper.text()).not.toContain('Conta conectada');
    expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
    await button(wrapper, 'Continuar com o Instagram').trigger('click');
    await flushPromises();
    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith(
      { tester_selection_token: candidate.selection_token },
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(button(wrapper, 'Continuar com o Instagram')).toBeUndefined();
    expect(button(wrapper, 'Verificar convite')).toBeDefined();
    expect(wrapper.text()).toContain('Não foi possível autorizar');
  });

  it('invites only on click and blocks duplicated submit and profile switch during send', async () => {
    instagramClient.getTesterStatus.mockResolvedValue({
      data: { status: 'absent' },
    });
    let resolveInvite;
    instagramClient.inviteTester.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveInvite = resolve;
        })
    );
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    expect(instagramClient.inviteTester).not.toHaveBeenCalled();
    await button(wrapper, 'Enviar convite').trigger('click');
    await button(wrapper, 'Enviando convite…').trigger('click');
    expect(instagramClient.inviteTester).toHaveBeenCalledTimes(1);
    expect(
      button(wrapper, 'Trocar perfil').attributes('disabled')
    ).toBeDefined();
    resolveInvite({ data: { status: 'pending', invited: true } });
    await flushPromises();
    expect(wrapper.text()).toContain('Convite enviado');
    expect(button(wrapper, 'Já aceitei — verificar')).toBeDefined();
  });

  it.each([{}, { status: 'pending' }])(
    'never infers send success from malformed 200 response %j',
    async data => {
      instagramClient.getTesterStatus.mockResolvedValue({
        data: { status: 'absent' },
      });
      instagramClient.inviteTester.mockResolvedValue({ data });
      const wrapper = mountTester();
      await searchAndSelect(wrapper);
      await button(wrapper, 'Enviar convite').trigger('click');
      await flushPromises();
      expect(wrapper.text()).not.toContain('Convite enviado');
      expect(wrapper.text()).toContain('Não foi possível confirmar o envio');
      expect(button(wrapper, 'Enviar convite')).toBeUndefined();
      expect(button(wrapper, 'Verificar convite')).toBeDefined();
    }
  );

  it('reconciles timeout before allowing any new invite', async () => {
    instagramClient.getTesterStatus.mockResolvedValue({
      data: { status: 'absent' },
    });
    instagramClient.inviteTester.mockRejectedValue(new Error('timeout'));
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    await button(wrapper, 'Enviar convite').trigger('click');
    await flushPromises();
    expect(button(wrapper, 'Enviar convite')).toBeUndefined();
    await button(wrapper, 'Verificar convite').trigger('click');
    await flushPromises();
    expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
    expect(button(wrapper, 'Enviar convite')).toBeDefined();
    expect(instagramClient.inviteTester).toHaveBeenCalledTimes(1);
  });

  it.each(['unknown_status', 'unexpected_code', 'meta_session_expired'])(
    'keeps status failure %s closed with no raw provider error',
    async errorCode => {
      instagramClient.getTesterStatus.mockRejectedValue({
        response: {
          data: { error_code: errorCode, message: 'PRIVATE META RESPONSE' },
        },
      });
      const wrapper = mountTester();
      await searchAndSelect(wrapper);
      expect(wrapper.find('[role="alert"]').exists()).toBe(true);
      expect(wrapper.text()).not.toContain('PRIVATE META RESPONSE');
      expect(button(wrapper, 'Enviar convite')).toBeUndefined();
      expect(button(wrapper, 'Continuar com o Instagram')).toBeUndefined();
    }
  );

  it('expired selection returns to search and discards signed results', async () => {
    instagramClient.getTesterStatus.mockRejectedValue({
      response: { data: { error_code: 'invalid_selection' } },
    });
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    expect(wrapper.text()).toContain('Selecione o perfil novamente');
    expect(wrapper.find('input').exists()).toBe(true);
    expect(wrapper.find('input').element.value).toBe('@demo_company');
    expect(
      wrapper
        .find('[aria-label="Selecionar @demo_company, Empresa Demo"]')
        .exists()
    ).toBe(false);
  });

  it('ignores old searches even when the adapter resolves after cancellation', async () => {
    let resolveOld;
    instagramClient.searchTesters.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mountTester();
    await flushPromises();
    await wrapper.find('input').setValue('old_company');
    await wrapper.find('form').trigger('submit');
    const signal = instagramClient.searchTesters.mock.calls[0][1].signal;
    await wrapper.find('input').setValue('demo_company');
    expect(signal.aborted).toBe(true);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    resolveOld({
      data: { results: [{ ...candidate, username: 'old_company' }] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('@demo_company');
    expect(wrapper.text()).not.toContain('@old_company');
  });

  it('cancels requests on unmount without surfacing cancellation errors', async () => {
    instagramClient.searchTesters.mockImplementation(
      () => new Promise(() => {})
    );
    const wrapper = mountTester();
    await flushPromises();
    await wrapper.find('input').setValue('demo_company');
    await wrapper.find('form').trigger('submit');
    const signal = instagramClient.searchTesters.mock.calls[0][1].signal;
    wrapper.unmount();
    expect(signal.aborted).toBe(true);
  });

  it('account switch remounts and aborts status instead of reusing selection', async () => {
    config.value.instagramTesterAutomationEnabled = true;
    instagramClient.getTesterStatus.mockImplementation(
      () => new Promise(() => {})
    );
    const wrapper = mount(Instagram, mountOptions);
    await searchAndSelect(wrapper);
    const signal = instagramClient.getTesterStatus.mock.calls[0][1].signal;
    accountId.value = 18;
    await flushPromises();
    expect(signal.aborted).toBe(true);
    expect(wrapper.find('input').exists()).toBe(true);
    expect(wrapper.find('input').element.value).toBe('');
    expect(instagramClient.getTesterConfiguration).toHaveBeenCalledTimes(2);
  });

  it('preserves pending instructions after failed verification and supports wrong-account switch', async () => {
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    instagramClient.getTesterStatus.mockRejectedValue(new Error('network'));
    await button(wrapper, 'Já aceitei — verificar').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('ol li')).toHaveLength(4);
    await button(wrapper, 'Trocar perfil').trigger('click');
    expect(wrapper.find('input').element.value).toBe('@demo_company');
    expect(button(wrapper, 'Já aceitei — verificar')).toBeUndefined();
  });

  it('validates username and associates field help and error', async () => {
    const wrapper = mountTester();
    await flushPromises();
    await wrapper.find('input').setValue('@@bad profile');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.find('input').attributes('aria-invalid')).toBe('true');
    expect(wrapper.find('input').attributes('aria-describedby')).toContain(
      'instagram-tester-error'
    );
    expect(instagramClient.searchTesters).not.toHaveBeenCalled();
  });

  it('search errors and malformed old search schema can recover through explicit search', async () => {
    instagramClient.searchTesters.mockRejectedValueOnce(new Error('network'));
    const wrapper = mountTester();
    await flushPromises();
    await wrapper.find('input').setValue('demo_company');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('Não foi possível buscar');
    instagramClient.searchTesters.mockResolvedValueOnce({
      data: { payload: { entries: [candidate] } },
    });
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper
        .find('[aria-label="Selecionar @demo_company, Empresa Demo"]')
        .exists()
    ).toBe(false);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper
        .find('[aria-label="Selecionar @demo_company, Empresa Demo"]')
        .exists()
    ).toBe(true);
  });

  it('Meta incident restriction blocks invite and OAuth in the assisted flow', async () => {
    instagramClient.getTesterStatus.mockResolvedValue({
      data: { status: 'absent' },
    });
    const wrapper = mount(TesterOnboarding, {
      ...mountOptions,
      props: { accountId: 17, disabled: true },
    });
    await searchAndSelect(wrapper);
    expect(
      button(wrapper, 'Enviar convite').attributes('disabled')
    ).toBeDefined();
    await button(wrapper, 'Enviar convite').trigger('click');
    expect(instagramClient.inviteTester).not.toHaveBeenCalled();
    await button(wrapper, 'Trocar perfil').trigger('click');
    instagramClient.getTesterStatus.mockResolvedValue({
      data: { status: 'accepted' },
    });
    await searchAndSelect(wrapper);
    expect(
      button(wrapper, 'Continuar com o Instagram').attributes('disabled')
    ).toBeDefined();
  });

  it('configuration request failures stay closed and recover by retry', async () => {
    instagramClient.getTesterConfiguration.mockRejectedValueOnce(
      new Error('network')
    );
    const wrapper = mountTester();
    await flushPromises();
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.text()).toContain('Procure o suporte');
    await button(wrapper, 'Tentar novamente').trigger('click');
    await flushPromises();
    expect(wrapper.find('input').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('unknown status payload never enables an invite or OAuth', async () => {
    instagramClient.getTesterStatus.mockResolvedValue({
      data: { status: 'CONFIRMED' },
    });
    const wrapper = mountTester();
    await searchAndSelect(wrapper);
    expect(wrapper.text()).toContain('Não foi possível verificar');
    expect(button(wrapper, 'Enviar convite')).toBeUndefined();
    expect(button(wrapper, 'Continuar com o Instagram')).toBeUndefined();
  });

  it('duplicate search and status clicks issue only one request per operation', async () => {
    let resolveSearch;
    instagramClient.searchTesters.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveSearch = resolve;
        })
    );
    const wrapper = mountTester();
    await flushPromises();
    await wrapper.find('input').setValue('demo_company');
    await wrapper.find('form').trigger('submit');
    await wrapper.find('form').trigger('submit');
    expect(instagramClient.searchTesters).toHaveBeenCalledTimes(1);
    resolveSearch({ data: { results: [candidate] } });
    await flushPromises();
    await wrapper
      .find('[aria-label="Selecionar @demo_company, Empresa Demo"]')
      .trigger('click');
    await flushPromises();
    let resolveStatus;
    instagramClient.getTesterStatus.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveStatus = resolve;
        })
    );
    await button(wrapper, 'Já aceitei — verificar').trigger('click');
    await button(wrapper, 'Verificando convite…').trigger('click');
    expect(instagramClient.getTesterStatus).toHaveBeenCalledTimes(2);
    resolveStatus({ data: { status: 'pending' } });
    await flushPromises();
  });

  it('moves focus to state title and back to username for profile correction', async () => {
    const wrapper = mount(TesterOnboarding, {
      ...mountOptions,
      props: { accountId: 17 },
      attachTo: document.body,
    });
    await searchAndSelect(wrapper);
    expect(document.activeElement).toBe(wrapper.find('h2').element);
    await button(wrapper, 'Trocar perfil').trigger('click');
    await flushPromises();
    expect(document.activeElement).toBe(wrapper.find('input').element);
  });

  it('renders English guidance from the same catalog and never truncates action slots', async () => {
    i18n.global.locale.value = 'en';
    const wrapper = mountTester();
    await flushPromises();
    await wrapper.find('input').setValue('demo_company');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    await wrapper
      .find('[aria-label="Select @demo_company, Empresa Demo"]')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('In a computer browser');
    expect(
      button(wrapper, 'I’ve accepted — check again')
        .find('span.whitespace-normal')
        .exists()
    ).toBe(true);
  });
});
