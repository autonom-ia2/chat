import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import MessageReactions from '../MessageReactions.vue';
import {
  canEdit,
  canReact,
  groupReactions,
  myReaction,
  EDIT_WINDOW_SECONDS,
} from '../messageActions.js';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../constants';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const AGORA = 1_000_000;
const conversa = actions => ({ whatsapp_api_message_actions: actions });
const nossa = (extra = {}) => ({
  messageType: MESSAGE_TYPES.OUTGOING,
  private: false,
  contentType: 'text',
  attachments: [],
  contentAttributes: {},
  status: MESSAGE_STATUS.SENT,
  createdAt: AGORA - 60,
  ...extra,
});

describe('quando o painel oferece reagir e editar', () => {
  it('só com a ação no campo da conversa', () => {
    expect(canReact(conversa([]), nossa())).toBe(false);
    expect(canReact(conversa(['react']), nossa())).toBe(true);
    expect(canEdit(conversa(['react']), nossa(), AGORA)).toBe(false);
    expect(canEdit(conversa(['edit']), nossa(), AGORA)).toBe(true);
    expect(canReact(undefined, nossa())).toBe(false);
  });

  it('não reage a nota, atividade nem mensagem apagada', () => {
    const acoes = conversa(['react']);
    expect(canReact(acoes, nossa({ private: true }))).toBe(false);
    expect(
      canReact(acoes, nossa({ messageType: MESSAGE_TYPES.ACTIVITY }))
    ).toBe(false);
    expect(
      canReact(acoes, nossa({ contentAttributes: { deleted: true } }))
    ).toBe(false);
    expect(
      canReact(acoes, nossa({ messageType: MESSAGE_TYPES.INCOMING }))
    ).toBe(true);
  });

  it('só edita texto nosso, sem anexo nem formato, dentro da janela', () => {
    const acoes = conversa(['edit']);
    const foraDaJanela = nossa({ createdAt: AGORA - EDIT_WINDOW_SECONDS - 1 });

    expect(canEdit(acoes, foraDaJanela, AGORA)).toBe(false);
    expect(
      canEdit(acoes, nossa({ messageType: MESSAGE_TYPES.INCOMING }), AGORA)
    ).toBe(false);
    expect(canEdit(acoes, nossa({ attachments: [{ id: 1 }] }), AGORA)).toBe(
      false
    );
    expect(
      canEdit(
        acoes,
        nossa({ contentAttributes: { richMessage: { type: 'options' } } }),
        AGORA
      )
    ).toBe(false);
    expect(
      canEdit(acoes, nossa({ status: MESSAGE_STATUS.FAILED }), AGORA)
    ).toBe(false);
  });
});

describe('reações na mensagem', () => {
  const reacoes = [
    { emoji: '👍', by: 'contact' },
    { emoji: '👍', by: 'agent', userId: 7 },
    { emoji: '❤️', by: 'phone' },
  ];

  it('agrupa por emoji e marca a do atendente', () => {
    expect(groupReactions(reacoes, 7)).toEqual([
      { emoji: '👍', count: 2, mine: true },
      { emoji: '❤️', count: 1, mine: false },
    ]);
    expect(myReaction(reacoes, 7)).toBe('👍');
    expect(myReaction(reacoes, 8)).toBe('');
  });

  it('desenha o chip com a contagem', () => {
    const wrapper = mount(MessageReactions, {
      props: { reactions: reacoes, currentUserId: 7 },
    });

    expect(
      wrapper.findAll('li').map(item =>
        item
          .findAll('span')
          .map(span => span.text())
          .join('')
      )
    ).toEqual(['👍2', '❤️']);
  });
});
