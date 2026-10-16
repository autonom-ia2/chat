import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import MessageReactions from '../MessageReactions.vue';
import EditedMark from '../EditedMark.vue';
import {
  canEdit,
  canReact,
  groupReactions,
  businessReaction,
  EDIT_WINDOW_SECONDS,
  EDIT_WINDOW_MINUTES,
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

  it('não reage a nota, atividade, mensagem apagada nem falhada', () => {
    const acoes = conversa(['react']);
    expect(canReact(acoes, nossa({ private: true }))).toBe(false);
    expect(
      canReact(acoes, nossa({ messageType: MESSAGE_TYPES.ACTIVITY }))
    ).toBe(false);
    expect(
      canReact(acoes, nossa({ contentAttributes: { deleted: true } }))
    ).toBe(false);
    expect(canReact(acoes, nossa({ status: MESSAGE_STATUS.FAILED }))).toBe(
      false
    );
    expect(
      canReact(acoes, nossa({ contentAttributes: { externalError: 'x' } }))
    ).toBe(false);
    expect(
      canReact(acoes, nossa({ messageType: MESSAGE_TYPES.INCOMING }))
    ).toBe(true);
  });

  it('só edita texto nosso, sem anexo nem formato, dentro da janela', () => {
    const acoes = conversa(['edit']);
    const foraDaJanela = nossa({ createdAt: AGORA - EDIT_WINDOW_SECONDS - 1 });

    expect(EDIT_WINDOW_MINUTES).toBe(14);
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
    expect(
      canEdit(
        acoes,
        nossa({ contentAttributes: { externalError: 'x' } }),
        AGORA
      )
    ).toBe(false);
  });
});

describe('reações na mensagem', () => {
  const reacoes = [
    { emoji: '👍', senderType: 'Contact', senderId: 3 },
    { emoji: '👍', senderType: 'User', senderId: 7 },
  ];

  it('a reação da empresa é uma só, de qualquer atendente ou do celular', () => {
    expect(groupReactions(reacoes, 7)).toEqual([
      {
        emoji: '👍',
        count: 2,
        fromContact: true,
        fromBusiness: true,
        mine: true,
      },
    ]);
    expect(groupReactions(reacoes, 8)[0].mine).toBe(false);
    expect(businessReaction(reacoes)).toBe('👍');
    expect(
      businessReaction([{ emoji: '❤️', senderType: 'User', senderId: null }])
    ).toBe('❤️');
    expect(
      businessReaction([{ emoji: '❤️', senderType: 'Contact', senderId: 3 }])
    ).toBe('');
  });

  it('diz em texto quem reagiu e destaca a do cliente', () => {
    const wrapper = mount(MessageReactions, {
      props: {
        reactions: [
          { emoji: '👍', senderType: 'Contact', senderId: 3 },
          { emoji: '❤️', senderType: 'User', senderId: 7 },
        ],
        currentUserId: 7,
      },
    });

    const itens = wrapper.findAll('li');
    expect(itens.map(item => item.find('.sr-only').text())).toEqual([
      '👍 do cliente',
      '❤️ da empresa, feita por você',
    ]);
    expect(itens[0].attributes('data-reaction-from-contact')).toBe('true');
    expect(itens[1].attributes('data-reaction-from-contact')).toBeUndefined();
  });
});

describe('selo "editada"', () => {
  const historico = [
    {
      content: 'Até logo',
      senderType: 'Contact',
      senderId: 3,
      editedAt: '2026-10-16T10:00:00Z',
    },
    {
      content: 'Até já',
      senderType: 'User',
      senderId: 7,
      editedAt: '2026-10-16T10:01:00Z',
    },
    {
      content: 'Até mais',
      senderType: 'User',
      senderId: null,
      editedAt: '2026-10-16T10:02:00Z',
    },
  ];

  it('é um botão que abre os textos anteriores com quem editou', async () => {
    const wrapper = mount(EditedMark, {
      props: { history: historico, currentUserId: 7 },
    });
    const botao = wrapper.find('button');

    expect(botao.attributes('aria-expanded')).toBe('false');
    expect(wrapper.find('[data-edit-history]').isVisible()).toBe(false);

    await botao.trigger('click');

    expect(botao.attributes('aria-expanded')).toBe('true');
    expect(botao.attributes('aria-controls')).toBe(
      wrapper.find('[data-edit-history]').attributes('id')
    );
    expect(wrapper.find('[data-edit-history]').text()).toContain(
      'Cliente escreveu antes:'
    );
    expect(wrapper.find('[data-edit-history]').text()).toContain(
      'Antes da sua edição:'
    );
    expect(wrapper.find('[data-edit-history]').text()).toContain('Até já');
    expect(wrapper.find('[data-edit-history]').text()).toContain(
      'Antes da edição no celular da empresa:'
    );
  });
});
