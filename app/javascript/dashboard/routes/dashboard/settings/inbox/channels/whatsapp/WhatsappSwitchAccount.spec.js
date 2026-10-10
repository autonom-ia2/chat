import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import InboxHealthAPI from 'dashboard/api/inboxHealth';
import WhatsappSwitchAccount from './WhatsappSwitchAccount.vue';
import { setupFacebookSdk } from './utils';

const runEmbeddedSignup = vi.fn();

vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({ runEmbeddedSignup }),
}));
vi.mock('./utils', () => ({
  setupFacebookSdk: vi.fn(() => Promise.resolve()),
}));
vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { reauthorizeWhatsApp: vi.fn() },
}));
vi.mock('dashboard/api/inboxHealth', () => ({
  default: { registerWebhook: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  Dialog: {
    template: '<div><slot /></div>',
    methods: { open() {}, close() {} },
  },
  Button: {
    props: ['label', 'disabled', 'isLoading'],
    emits: ['click'],
    template:
      '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
  },
  Checkbox: {
    props: ['modelValue'],
    emits: ['update:modelValue'],
    template:
      '<input type="checkbox" :checked="modelValue" @change="$emit(\'update:modelValue\', $event.target.checked)" />',
  },
};

const CREDENTIALS = {
  code: 'auth-code',
  business_id: 'gta-portfolio',
  waba_id: 'gta-waba',
  phone_number_id: 'gta-phone',
  is_coexistence: false,
};

const mountCard = () =>
  mount(WhatsappSwitchAccount, {
    props: {
      inbox: { id: 1, phone_number: '+5511978622068' },
      healthData: {
        display_phone_number: '+55 11 97862-2068',
        verified_name: 'GTA Assist',
        business_portfolio_name: 'Autonom.ia',
      },
    },
    global: { stubs },
  });

const buttonByLabel = (wrapper, label) =>
  wrapper.findAll('button').find(button => button.text() === label);

const confirmChecklist = async wrapper => {
  await wrapper.find('[data-test="switch-account-open"]').trigger('click');
  await flushPromises();
  await wrapper
    .find('[data-test="check-left-old-account"] input')
    .setValue(true);
  await wrapper.find('[data-test="check-phone-at-hand"] input').setValue(true);
};

const openFacebook = async wrapper => {
  await buttonByLabel(
    wrapper,
    'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.OPEN_FACEBOOK'
  ).trigger('click');
  await flushPromises();
};

describe('WhatsappSwitchAccount', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    runEmbeddedSignup.mockResolvedValue(CREDENTIALS);
    whatsappChannel.reauthorizeWhatsApp.mockResolvedValue({
      data: { success: true, ready_to_receive: true },
    });
  });

  it('shows who owns the account today', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('GTA Assist');
    expect(wrapper.text()).toContain('Autonom.ia');
  });

  it('only opens Facebook after both confirmations', async () => {
    const wrapper = mountCard();
    await wrapper.find('[data-test="switch-account-open"]').trigger('click');
    await flushPromises();
    const openButton = () =>
      buttonByLabel(
        wrapper,
        'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.OPEN_FACEBOOK'
      );

    expect(openButton().attributes('disabled')).toBeDefined();
    await wrapper
      .find('[data-test="check-left-old-account"] input')
      .setValue(true);
    expect(openButton().attributes('disabled')).toBeDefined();
    await wrapper
      .find('[data-test="check-phone-at-hand"] input')
      .setValue(true);
    expect(openButton().attributes('disabled')).toBeUndefined();
  });

  it('sends the IDs Meta returned, not the stored ones', async () => {
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);

    expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledWith({
      inboxId: 1,
      ...CREDENTIALS,
    });
    expect(wrapper.find('[data-test="switch-account-done"]').exists()).toBe(
      true
    );
    expect(wrapper.emitted('switched')).toHaveLength(1);
  });

  it('tells the user which number to pick when Meta returns another one', async () => {
    whatsappChannel.reauthorizeWhatsApp.mockRejectedValue({
      response: {
        data: {
          error_code: 'phone_number_mismatch',
          received_phone_number: '+5511944547873',
        },
      },
    });
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);

    expect(wrapper.find('[data-test="switch-account-mismatch"]').exists()).toBe(
      true
    );
    expect(wrapper.vm.receivedNumber).toBe('+5511944547873');
    expect(wrapper.emitted('switched')).toBeUndefined();
  });

  it('changes nothing when the Facebook window is closed', async () => {
    runEmbeddedSignup.mockResolvedValue(null);
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);

    expect(whatsappChannel.reauthorizeWhatsApp).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-test="switch-account-cancelled"]').exists()
    ).toBe(true);
  });

  it('sends the user back to the checklist after a Meta error', async () => {
    runEmbeddedSignup.mockRejectedValue(new Error('Number still registered'));
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);

    expect(wrapper.find('[data-test="switch-account-failed"]').exists()).toBe(
      true
    );
    await wrapper
      .find('[data-test="switch-account-try-again"]')
      .trigger('click');

    expect(wrapper.vm.step).toBe('checklist');
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
  });

  it('opens Facebook again right away after a wrong number', async () => {
    whatsappChannel.reauthorizeWhatsApp.mockRejectedValueOnce({
      response: { status: 422, data: { error_code: 'phone_number_mismatch' } },
    });
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);
    await wrapper
      .find('[data-test="switch-account-try-again"]')
      .trigger('click');
    await flushPromises();

    expect(runEmbeddedSignup).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-test="switch-account-done"]').exists()).toBe(
      true
    );
  });

  it('does not claim a result when the server did not answer', async () => {
    whatsappChannel.reauthorizeWhatsApp.mockRejectedValue(
      new Error('Network Error')
    );
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);

    expect(wrapper.find('[data-test="switch-account-unknown"]').exists()).toBe(
      true
    );
    expect(wrapper.emitted('switched')).toHaveLength(1);
  });

  it('keeps the running flow when the dialog is closed and reopened', async () => {
    let finishSignup;
    runEmbeddedSignup.mockReturnValue(
      new Promise(resolve => {
        finishSignup = resolve;
      })
    );
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);
    expect(wrapper.vm.step).toBe('facebook');

    await wrapper.find('[data-test="switch-account-open"]').trigger('click');
    expect(wrapper.vm.step).toBe('facebook');

    finishSignup(CREDENTIALS);
    await flushPromises();

    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
    expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-test="switch-account-done"]').exists()).toBe(
      true
    );
  });

  it('keeps Facebook closed while its script cannot load', async () => {
    setupFacebookSdk.mockRejectedValueOnce(new Error('blocked'));
    const wrapper = mountCard();
    await confirmChecklist(wrapper);

    expect(
      buttonByLabel(
        wrapper,
        'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.OPEN_FACEBOOK'
      ).attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.SDK_ERROR'
    );
  });

  it('offers to connect receiving when the webhook did not stick', async () => {
    whatsappChannel.reauthorizeWhatsApp.mockResolvedValue({
      data: { success: true, ready_to_receive: false },
    });
    InboxHealthAPI.registerWebhook.mockRejectedValueOnce(new Error('meta'));
    InboxHealthAPI.registerWebhook.mockResolvedValueOnce({});
    const wrapper = mountCard();
    await confirmChecklist(wrapper);
    await openFacebook(wrapper);
    const retryButton = () =>
      buttonByLabel(
        wrapper,
        'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.RETRY_RECEIVING'
      );

    expect(
      wrapper.find('[data-test="switch-account-not_ready"]').exists()
    ).toBe(true);
    await retryButton().trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.RESULTS.RETRY_FAILED'
    );

    await retryButton().trigger('click');
    await flushPromises();

    expect(InboxHealthAPI.registerWebhook).toHaveBeenCalledWith(1);
    expect(wrapper.find('[data-test="switch-account-done"]').exists()).toBe(
      true
    );
  });
});
