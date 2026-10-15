import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import TextBubble from '../Text/Index.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('dashboard/composables/useTranslations', async () => {
  const { ref: vueRef } = await import('vue');
  return {
    useTranslations: () => ({
      hasTranslations: vueRef(false),
      translationContent: vueRef(''),
    }),
  };
});

// chat#1489: o texto que o WhatsApp API trouxe do celular ganha um selo discreto.
const mountText = contentAttributes => {
  const TestHost = defineComponent({
    components: { TextBubble },
    setup() {
      provideMessageContext({
        content: ref('Seu boleto vence amanhã.'),
        attachments: ref([]),
        contentAttributes: ref(contentAttributes),
        messageType: ref(0),
        status: ref('sent'),
      });
    },
    template: '<TextBubble />',
  });

  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        CONVERSATION: {
          HYBRID_RECOVERY: {
            RECOVERED: 'recovered from the phone',
            MEDIA: 'This message has media. Check it on the phone.',
          },
        },
      },
    },
  });

  return mount(TestHost, {
    global: {
      plugins: [i18n],
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        FormattedContent: {
          props: ['content'],
          template: '<p>{{ content }}</p>',
        },
        AttachmentChips: true,
        TranslationToggle: true,
      },
    },
  });
};

const note = wrapper => wrapper.find('[data-test-id="hybrid-recovery-note"]');

describe('Text bubble recovered from the phone', () => {
  it('shows the recovered content with a small badge', () => {
    const wrapper = mountText({ hybridRecovery: 'recovered' });

    expect(wrapper.text()).toContain('Seu boleto vence amanhã.');
    expect(note(wrapper).text()).toBe('recovered from the phone');
  });

  it('shows the media notice next to a recovered caption', () => {
    const wrapper = mountText({
      hybridRecovery: 'failed',
      hybridRecoveryReason: 'media',
    });

    expect(note(wrapper).text()).toBe(
      'This message has media. Check it on the phone.'
    );
  });

  it('shows no badge on ordinary messages', () => {
    expect(note(mountText({})).exists()).toBe(false);
  });
});
