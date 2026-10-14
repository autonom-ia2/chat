import { mount } from '@vue/test-utils';
import { montagem } from './montarMensagem';
import MessageList from '../MessageList.vue';

// A mensagem como o servidor entrega (snake_case): a lista é quem converte as chaves para a bolha.
const DO_SERVIDOR = {
  id: 41,
  content: 'Você escolhe o dia e a hora pelo nosso site.',
  inbox_id: 3,
  conversation_id: 7,
  message_type: 1,
  content_type: 'text',
  status: 'sent',
  private: false,
  created_at: Math.floor(Date.now() / 1000),
  source_id: 'wamid.exemplo',
  sender: { id: 1, name: 'Assistente virtual', type: 'agent_bot' },
  content_attributes: {
    rich_message: {
      type: 'link_button',
      label: 'Escolher horário',
      url: 'https://exemplo.com.br/agendar?origem=whatsapp',
      header: 'Agendamento',
      footer: 'Leva um minuto.',
    },
  },
};

const mountList = messages =>
  mount(MessageList, {
    props: { currentUserId: 1, messages },
    global: montagem,
  });

describe('MessageList', () => {
  it('mostra o botão de link da mensagem como ela vem do servidor', () => {
    const wrapper = mountList([DO_SERVIDOR]);
    const bubble = wrapper.get('[data-bubble-name="rich-link-button"]');

    expect(bubble.text()).toContain('Agendamento');
    expect(bubble.text()).toContain(DO_SERVIDOR.content);
    expect(bubble.text()).toContain('Leva um minuto.');
    expect(bubble.get('a').text()).toContain('Escolher horário');
    expect(bubble.get('a').attributes('href')).toBe(
      DO_SERVIDOR.content_attributes.rich_message.url
    );
  });

  it('escreve o motivo da falha que vem em external_error', () => {
    const wrapper = mountList([
      {
        ...DO_SERVIDOR,
        status: 'failed',
        content_attributes: {
          ...DO_SERVIDOR.content_attributes,
          external_error: 'O texto do botão de link passa de 20 caracteres.',
        },
      },
    ]);

    expect(wrapper.text()).toContain(
      'O texto do botão de link passa de 20 caracteres.'
    );
    expect(wrapper.find('button').exists()).toBe(true);
  });
});
