import { mount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
  useRoute: () => ({ name: 'contacts_edit', params: { accountId: 1 } }),
}));

// #2255 — o card do histórico do contato: o contato que só tem o número aparece com o
// telefone legível, e a caixa do WhatsApp do celular leva o ícone do WhatsApp.
const montar = ({ contact, stateInbox }) =>
  mount(ConversationCard, {
    props: {
      conversation: { id: 7, messages: [], timestamp: 0 },
      contact,
      stateInbox,
      accountLabels: [],
    },
    global: {
      stubs: {
        Avatar: { props: ['name'], template: '<i data-avatar>{{ name }}</i>' },
        Icon: { props: ['icon'], template: '<i data-icone>{{ icon }}</i>' },
        CardMessagePreview: true,
        CardMessagePreviewWithMeta: true,
        CardPriorityIcon: true,
      },
    },
  });

describe('ConversationCard', () => {
  it('mostra o telefone legível quando o nome é só o número', () => {
    const wrapper = montar({
      contact: { name: '5511955554444', phoneNumber: '+5511955554444' },
      stateInbox: { channelType: 'Channel::Api', wahaProvider: true },
    });

    expect(wrapper.find('h4').text()).toBe('+55 11 95555-4444');
    expect(wrapper.find('[data-avatar]').text()).toBe('+55 11 95555-4444');
    expect(wrapper.find('[data-icone]').text()).toBe('i-ri-whatsapp-fill');
  });

  it('mantém o nome gravado e o ícone de API na caixa API comum', () => {
    const wrapper = montar({
      contact: { name: 'Marina Demo', phoneNumber: '+5511944443333' },
      stateInbox: { channelType: 'Channel::Api' },
    });

    expect(wrapper.find('h4').text()).toBe('Marina Demo');
    expect(wrapper.find('[data-icone]').text()).toBe('i-ri-cloudy-fill');
  });
});
