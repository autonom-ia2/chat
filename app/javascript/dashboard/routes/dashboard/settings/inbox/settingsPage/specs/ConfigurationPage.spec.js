import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConfigurationPage from '../ConfigurationPage.vue';
import SmtpSettings from '../../SmtpSettings.vue';
import HmacSecretKey from '../components/HmacSecretKey.vue';
import { useAlert } from 'dashboard/composables';

const { runEmbeddedSignup, getInboxes } = vi.hoisted(() => ({
  runEmbeddedSignup: vi.fn(),
  getInboxes: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({ runEmbeddedSignup }),
  SIGNUP_TIMEOUT_CODE: 'WHATSAPP_SIGNUP_TIMEOUT',
}));

const ADMIN = ['administrator'];

const mountComponent = (inbox, permissions = ADMIN) =>
  shallowMount(ConfigurationPage, {
    props: { inbox },
    global: {
      plugins: [
        createStore({
          getters: {
            'globalConfig/isOnChatwootCloud': () => true,
            getCurrentUser: () => ({ accounts: [{ id: 1, permissions }] }),
            getCurrentAccountId: () => 1,
          },
          actions: { 'inboxes/get': getInboxes },
        }),
      ],
      mocks: {
        $t: key => key,
      },
      stubs: {
        SettingsFieldSection: {
          template: '<section><slot /></section>',
        },
        NextButton: {
          template: '<button><slot /></button>',
        },
        'woot-code': true,
        'woot-input': true,
        WhatsappBusinessManagementToken: true,
      },
    },
  });

describe('ConfigurationPage', () => {
  it.each([false, true])(
    'shows SMTP settings for email inboxes when IMAP is %s',
    imapEnabled => {
      const inbox = {
        channel_type: 'Channel::Email',
        imap_enabled: imapEnabled,
      };
      const wrapper = mountComponent(inbox);

      expect(wrapper.findComponent(SmtpSettings).exists()).toBe(true);
      expect(wrapper.findComponent(SmtpSettings).props('inbox')).toEqual(inbox);
    }
  );

  it('shows the WhatsApp reconfigure option for embedded signup inboxes without checking account feature flags', () => {
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'embedded_signup',
        webhook_verify_token: 'verify-token',
      },
    });

    expect(wrapper.vm.showWhatsAppReconfigure).toBe(true);
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON'
    );
  });

  // #2027: trocar a credencial de uma caixa existente pede integration_manage.
  it('hides IMAP/SMTP and the WhatsApp reconfigure without integration_manage', () => {
    const emailPage = mountComponent({ channel_type: 'Channel::Email' }, [
      'inbox_manage',
    ]);
    expect(emailPage.findComponent(SmtpSettings).exists()).toBe(false);

    const whatsappPage = mountComponent(
      {
        channel_type: 'Channel::Whatsapp',
        provider: 'whatsapp_cloud',
        provider_config: { source: 'embedded_signup' },
      },
      ['inbox_manage']
    );
    expect(whatsappPage.vm.showWhatsAppReconfigure).toBe(false);
  });

  it('shows IMAP/SMTP to a role with integration_manage', () => {
    const wrapper = mountComponent({ channel_type: 'Channel::Email' }, [
      'integration_manage',
    ]);
    expect(wrapper.findComponent(SmtpSettings).exists()).toBe(true);
  });

  it('shows the HMAC key only when the server sent the token', () => {
    const without = mountComponent({ channel_type: 'Channel::Api' }, [
      'inbox_manage',
    ]);
    expect(without.findComponent(HmacSecretKey).exists()).toBe(false);

    const withToken = mountComponent(
      { channel_type: 'Channel::Api', hmac_token: 'hmac' },
      ['token_manage']
    );
    expect(withToken.findComponent(HmacSecretKey).exists()).toBe(true);
  });

  it('does not show the WhatsApp reconfigure option for manual WhatsApp inboxes', () => {
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: {
        source: 'manual_setup_v2',
        webhook_verify_token: 'verify-token',
      },
    });

    expect(wrapper.vm.showWhatsAppReconfigure).toBe(false);
  });
});

// #1228: Meta may have finished the reconfigure; do not show the generic error.
describe('ConfigurationPage WhatsApp reconfigure that Facebook did not confirm', () => {
  it('refreshes the inboxes and says the connection was not confirmed', async () => {
    runEmbeddedSignup.mockRejectedValueOnce(
      Object.assign(new Error('timed out'), { code: 'WHATSAPP_SIGNUP_TIMEOUT' })
    );
    const wrapper = mountComponent({
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
      provider_config: { source: 'embedded_signup' },
    });

    await wrapper.vm.reconfigureWhatsApp();

    expect(getInboxes).toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.NOT_CONFIRMED'
    );
    expect(wrapper.vm.isReconfiguring).toBe(false);
  });
});
