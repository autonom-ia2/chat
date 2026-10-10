import { shallowMount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import WhatsappEmbeddedSignup from '../WhatsappEmbeddedSignup.vue';

const { runEmbeddedSignup, dispatch } = vi.hoisted(() => ({
  runEmbeddedSignup: vi.fn(),
  dispatch: vi.fn(),
}));

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ replace: vi.fn() }) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  I18nT: { template: '<span><slot /></span>' },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup', async () => {
  const { ref } = await import('vue');
  return {
    useWhatsappEmbeddedSignup: () => ({
      isAuthenticating: ref(false),
      runEmbeddedSignup,
    }),
    SIGNUP_TIMEOUT_CODE: 'WHATSAPP_SIGNUP_TIMEOUT',
  };
});

// #1228: Meta may have finished the signup; never show the technical timeout text.
describe('WhatsappEmbeddedSignup', () => {
  it('refreshes the inboxes and says the connection was not confirmed when Facebook times out', async () => {
    runEmbeddedSignup.mockRejectedValueOnce(
      Object.assign(
        new Error('WhatsApp signup timed out waiting for business data'),
        {
          code: 'WHATSAPP_SIGNUP_TIMEOUT',
        }
      )
    );
    const wrapper = shallowMount(WhatsappEmbeddedSignup);

    await wrapper.vm.launchEmbeddedSignup();

    expect(dispatch).toHaveBeenCalledWith('inboxes/get');
    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.NOT_CONFIRMED'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      expect.stringContaining('timed out')
    );
  });
});
