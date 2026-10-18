import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Unsupported from '../Unsupported.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('dashboard/composables/useInbox', async () => {
  const { ref: vueRef } = await import('vue');
  return {
    useInbox: () => ({
      isAFacebookInbox: vueRef(false),
      isAnInstagramChannel: vueRef(false),
      isATiktokChannel: vueRef(false),
      isAWhatsAppChannel: vueRef(true),
    }),
  };
});

const mountUnsupported = contentAttributes => {
  const TestHost = defineComponent({
    components: { Unsupported },
    setup() {
      provideMessageContext({
        inboxId: ref(1),
        contentAttributes: ref(contentAttributes),
      });
    },
    template: '<Unsupported />',
  });

  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        CONVERSATION: {
          UNSUPPORTED_MESSAGE_WHATSAPP: 'View it on the WhatsApp app.',
          HYBRID_RECOVERY: {
            PENDING: 'Fetching the content from the phone…',
            FAILED: "Couldn't recover this message. Check it on the phone.",
            MEDIA: 'This message has media. Check it on the phone.',
          },
        },
      },
    },
  });

  return mount(TestHost, {
    global: {
      plugins: [i18n],
      stubs: { BaseBubble: { template: '<div><slot /></div>' } },
    },
  });
};

describe('Unsupported bubble', () => {
  it('keeps the WhatsApp notice when there is no recovery', () => {
    expect(mountUnsupported({ isUnsupported: true }).text()).toBe(
      'View it on the WhatsApp app.'
    );
  });

  it('shows that the content is being fetched from the phone', () => {
    const wrapper = mountUnsupported({
      isUnsupported: true,
      hybridRecovery: 'pending',
    });
    expect(wrapper.text()).toBe('Fetching the content from the phone…');
  });

  it('asks to check the phone when the recovery failed', () => {
    expect(
      mountUnsupported({ isUnsupported: true, hybridRecovery: 'failed' }).text()
    ).toBe("Couldn't recover this message. Check it on the phone.");
    expect(
      mountUnsupported({
        isUnsupported: true,
        hybridRecovery: 'failed',
        hybridRecoveryReason: 'media',
      }).text()
    ).toBe('This message has media. Check it on the phone.');
  });
});
