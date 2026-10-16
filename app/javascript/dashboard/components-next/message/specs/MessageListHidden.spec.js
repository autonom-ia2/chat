import { mount } from '@vue/test-utils';
import { montagem } from './montarMensagem';
import MessageList from '../MessageList.vue';

// chat#1709 (fase 3): reação, edição, voto retirado e toque de ligação ficam como atividade escondida (`c2y_hidden`);
// a mudança aparece na mensagem a que se referem, com as reações e o selo "editada".
const base = {
  inbox_id: 3,
  conversation_id: 7,
  content_type: 'text',
  status: 'sent',
  private: false,
  created_at: Math.floor(Date.now() / 1000),
  sender: { id: 1, name: 'Ana', type: 'user' },
};

const mountList = messages =>
  mount(MessageList, {
    props: { currentUserId: 1, messages },
    global: montagem,
  });

describe('MessageList com registros escondidos', () => {
  it('não mostra a atividade escondida e mostra a reação e o selo na original', () => {
    const wrapper = mountList([
      {
        ...base,
        id: 41,
        message_type: 1,
        content: 'Até amanhã',
        content_attributes: {
          reactions: [
            {
              emoji: '👍',
              sender_type: 'Contact',
              sender_id: 3,
              at: '2026-10-16T10:00:00Z',
            },
          ],
          edited_at: '2026-10-16T10:01:00Z',
          edit_history: [
            {
              content: 'Até logo',
              edited_at: '2026-10-16T10:01:00Z',
              sender_type: 'Contact',
              sender_id: 3,
            },
          ],
        },
      },
      {
        ...base,
        id: 42,
        message_type: 2,
        content: '*Reagiu com* 👍',
        content_attributes: { c2y_hidden: true, reaction_applied_to: 41 },
      },
    ]);

    expect(wrapper.text()).not.toContain('Reagiu com');
    expect(wrapper.find('[data-message-reactions]').text()).toContain('👍');
    expect(wrapper.find('[data-edited-mark]').exists()).toBe(true);
  });

  it('nunca esconde mensagem do cliente ou nossa, mesmo com a chave', () => {
    const wrapper = mountList([
      {
        ...base,
        id: 43,
        message_type: 1,
        content: 'Saiu para o cliente',
        content_attributes: { c2y_hidden: true },
      },
      {
        ...base,
        id: 44,
        message_type: 0,
        content: 'Escrito pelo cliente',
        content_attributes: { c2y_hidden: true },
      },
    ]);

    expect(wrapper.text()).toContain('Saiu para o cliente');
    expect(wrapper.text()).toContain('Escrito pelo cliente');
  });
});
