import { shallowMount, flushPromises } from '@vue/test-utils';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import { useAlert } from 'dashboard/composables';
import Reauthorize from './Reauthorize.vue';
import {
  createMessageHandler,
  initWhatsAppEmbeddedSignup,
  setupFacebookSdk,
} from './utils';

// The real event classifier runs; only the Facebook SDK plumbing is stubbed.
vi.mock('./utils', async importOriginal => ({
  ...(await importOriginal()),
  setupFacebookSdk: vi.fn(),
  initWhatsAppEmbeddedSignup: vi.fn(),
  createMessageHandler: vi.fn(),
}));

vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { reauthorizeWhatsApp: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const EXISTING_CONFIG = {
  business_account_id: 'waba-1',
  phone_number_id: 'phone-1',
};

describe('WhatsApp Reauthorize', () => {
  let emitMetaEvent;

  const mountWith = providerConfig =>
    shallowMount(Reauthorize, {
      props: { inbox: { id: 7, provider_config: providerConfig } },
    });

  beforeEach(() => {
    vi.clearAllMocks();
    window.chatwootConfig = {
      whatsappAppId: 'app-id',
      whatsappConfigurationId: 'config-id',
    };
    setupFacebookSdk.mockResolvedValue();
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    whatsappChannel.reauthorizeWhatsApp.mockResolvedValue({
      data: { success: true },
    });
    createMessageHandler.mockImplementation(callback => {
      emitMetaEvent = callback;
      return () => {};
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('when the inbox already has its WhatsApp IDs', () => {
    // Production behavior before 4.18.0: reauthorize right after FB.login. The
    // terminal event is optional; without it the button must not spin forever.
    it('reauthorizes after the grace window when Meta sends no terminal event', async () => {
      vi.useFakeTimers();
      const wrapper = mountWith(EXISTING_CONFIG);
      await vi.runOnlyPendingTimersAsync();

      const pending = wrapper.vm.requestAuthorization();
      await vi.advanceTimersByTimeAsync(10 * 1000);
      await pending;

      expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledWith({
        inboxId: 7,
        code: 'auth-code',
        business_id: 'waba-1',
        waba_id: 'waba-1',
        phone_number_id: 'phone-1',
        is_coexistence: null,
      });
    });

    it('passes the coexistence signal when Meta sends a coexistence FINISH', async () => {
      const wrapper = mountWith(EXISTING_CONFIG);
      await flushPromises();

      const pending = wrapper.vm.requestAuthorization();
      emitMetaEvent({
        event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
        data: { waba_id: 'waba-1' },
      });
      await pending;

      expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledWith(
        expect.objectContaining({ is_coexistence: true })
      );
    });

    it('still reauthorizes on FINISH_GRANT_ONLY_API_ACCESS, with no coexistence signal', async () => {
      const wrapper = mountWith(EXISTING_CONFIG);
      await flushPromises();

      const pending = wrapper.vm.requestAuthorization();
      emitMetaEvent({
        event: 'FINISH_GRANT_ONLY_API_ACCESS',
        data: { waba_id: 'waba-1' },
      });
      await pending;

      expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledWith(
        expect.objectContaining({
          phone_number_id: 'phone-1',
          is_coexistence: null,
        })
      );
    });

    it('does not reauthorize when Meta reports a cancellation', async () => {
      const wrapper = mountWith(EXISTING_CONFIG);
      await flushPromises();

      const pending = wrapper.vm.requestAuthorization();
      emitMetaEvent({ event: 'CANCEL' });
      await pending;

      expect(whatsappChannel.reauthorizeWhatsApp).not.toHaveBeenCalled();
      expect(useAlert).toHaveBeenCalledWith(
        'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'
      );
    });
  });

  describe('when the inbox has no stored WhatsApp IDs', () => {
    it('reauthorizes a FINISH_ONLY_WABA with the WABA from the event', async () => {
      const wrapper = mountWith({});
      await flushPromises();

      await wrapper.vm.requestAuthorization();
      emitMetaEvent({ event: 'FINISH_ONLY_WABA', data: { waba_id: 'waba-9' } });
      await flushPromises();

      expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledWith({
        inboxId: 7,
        code: 'auth-code',
        business_id: '',
        waba_id: 'waba-9',
        phone_number_id: '',
        is_coexistence: null,
      });
    });

    it('shows Meta reason nested in data on an ERROR event', async () => {
      const wrapper = mountWith({});
      await flushPromises();

      await wrapper.vm.requestAuthorization();
      emitMetaEvent({
        event: 'ERROR',
        data: { error_message: 'Unable to connect this account' },
      });
      await flushPromises();

      expect(whatsappChannel.reauthorizeWhatsApp).not.toHaveBeenCalled();
      expect(useAlert).toHaveBeenCalledWith('Unable to connect this account');
    });
  });
});
