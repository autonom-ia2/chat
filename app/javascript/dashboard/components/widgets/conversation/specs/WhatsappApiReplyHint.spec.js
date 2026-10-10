import { shallowMount } from '@vue/test-utils';
import WhatsappApiReplyHint from '../WhatsappApiReplyHint.vue';

const mountHint = props =>
  shallowMount(WhatsappApiReplyHint, {
    props,
    global: { mocks: { $t: key => key } },
  });

describe('WhatsappApiReplyHint', () => {
  it('shows the hint when the reply goes through WhatsApp API', () => {
    const wrapper = mountHint({ conversation: { whatsapp_api_reply: true } });

    expect(wrapper.isVisible()).toBe(true);
    expect(wrapper.text()).toContain(
      'CONVERSATION.WHATSAPP_TRANSPORT.REPLY_HINT'
    );
  });

  it('hides the hint on private notes', () => {
    const wrapper = mountHint({
      conversation: { whatsapp_api_reply: true },
      isOnPrivateNote: true,
    });

    expect(wrapper.isVisible()).toBe(false);
  });

  it('hides the hint when the official window is open or the flag is missing', () => {
    expect(
      mountHint({ conversation: { whatsapp_api_reply: false } }).isVisible()
    ).toBe(false);
    expect(mountHint({ conversation: {} }).isVisible()).toBe(false);
    expect(mountHint({ conversation: null }).isVisible()).toBe(false);
  });
});
