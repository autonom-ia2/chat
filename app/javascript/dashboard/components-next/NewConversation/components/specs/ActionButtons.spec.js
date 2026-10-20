import { mount } from '@vue/test-utils';
import ActionButtons from '../ActionButtons.vue';

// chat#1457: caixa WhatsApp só com modelo não tem botão Enviar; com o Híbrido pronto, tem os dois.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'en' } }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    fetchSignatureFlagFromUISettings: () => false,
    setSignatureFlagForInbox: vi.fn(),
    isEditorHotKeyEnabled: () => false,
  }),
}));
vi.mock('dashboard/composables/useFileUpload', () => ({
  useFileUpload: () => ({ onFileUpload: vi.fn() }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

const SEND = 'COMPOSE_NEW_CONVERSATION.FORM.ACTION_BUTTONS.SEND';

const mountButtons = (props, attachTo) =>
  mount(ActionButtons, {
    attachTo,
    props: { hasSelectedInbox: true, inboxId: 7, ...props },
    global: {
      stubs: {
        WhatsAppOptions: { template: '<div data-test="template-picker" />' },
        ContentTemplateSelector: {
          template: '<div data-test="twilio-picker" />',
        },
        FileUpload: true,
        Icon: true,
        TeleportWithDirection: { template: '<slot />' },
        Button: {
          props: ['label'],
          template: '<button :data-label="label">{{ label }}</button>',
        },
      },
    },
  });

const hasSend = wrapper => wrapper.find(`[data-label="${SEND}"]`).exists();
const hasTemplatePicker = wrapper =>
  wrapper.find('[data-test="template-picker"]').exists();

describe('ActionButtons', () => {
  it('keeps the WhatsApp inbox template-only without the hybrid', () => {
    const wrapper = mountButtons({ isWhatsappInbox: true });

    expect(hasTemplatePicker(wrapper)).toBe(true);
    expect(hasSend(wrapper)).toBe(false);
  });

  it('offers free text next to the template when the hybrid is ready', () => {
    const wrapper = mountButtons({
      isWhatsappInbox: true,
      isWhatsappApiStart: true,
    });

    expect(hasTemplatePicker(wrapper)).toBe(true);
    expect(hasSend(wrapper)).toBe(true);
  });

  it('emits sendMessage from the send button on a hybrid inbox', async () => {
    const wrapper = mountButtons({
      isWhatsappInbox: true,
      isWhatsappApiStart: true,
    });

    await wrapper.find(`[data-label="${SEND}"]`).trigger('click');

    expect(wrapper.emitted('sendMessage')).toHaveLength(1);
  });

  it('keeps Twilio WhatsApp template-only', () => {
    const wrapper = mountButtons({ isTwilioWhatsAppInbox: true });

    expect(wrapper.find('[data-test="twilio-picker"]').exists()).toBe(true);
    expect(hasSend(wrapper)).toBe(false);
  });

  it('keeps the send button and no template picker on other inboxes', () => {
    const wrapper = mountButtons({ isEmailOrWebWidgetInbox: true });

    expect(hasTemplatePicker(wrapper)).toBe(false);
    expect(hasSend(wrapper)).toBe(true);
  });

  // #1895: a Nova conversa usa a janela de emojis própria do fork, como a resposta.
  it('opens the fork emoji window and emits the chosen emoji', async () => {
    const wrapper = mountButtons();
    expect(wrapper.find('[data-janela-de-emojis]').exists()).toBe(false);

    await wrapper.find('[data-emoji-da-nova-conversa]').trigger('click');
    expect(wrapper.find('[data-janela-de-emojis]').exists()).toBe(true);

    const primeiro = wrapper.find('[data-janela-de-emojis] .grid button');
    await primeiro.trigger('click');
    expect(wrapper.emitted('insertEmoji')).toEqual([[primeiro.text()]]);
  });

  it('closes the emoji window on Esc', async () => {
    const wrapper = mountButtons({}, document.body);
    await wrapper.find('[data-emoji-da-nova-conversa]').trigger('click');

    wrapper
      .find('[data-buscar-emoji]')
      .element.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
      );
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-janela-de-emojis]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('hides the emoji button on template-only WhatsApp', () => {
    const wrapper = mountButtons({ isWhatsappInbox: true });

    expect(wrapper.find('[data-emoji-da-nova-conversa]').exists()).toBe(false);
  });
});
