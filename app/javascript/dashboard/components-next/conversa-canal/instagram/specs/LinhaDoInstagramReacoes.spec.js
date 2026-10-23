import { computed } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import Message from 'dashboard/components-next/message/Message.vue';
import {
  AGORA,
  gettersDaMontagem,
  montagem,
} from 'dashboard/components-next/message/specs/montarMensagem';
import {
  MESSAGE_STATUS,
  MESSAGE_TYPES,
} from 'dashboard/components-next/message/constants';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));
vi.mock('dashboard/api/conversaCanal', () => ({
  default: { reagir: vi.fn() },
}));
vi.mock('../useConversaDoInstagram', async original => ({
  ...(await original()),
  useInstagramDaConversa: () => ({
    ligado: computed(() => true),
    fuso: computed(() => undefined),
    contato: computed(() => ({ name: 'Ana' })),
  }),
  useSequenciaDoInstagram: () => computed(() => new Map()),
}));

const CAIXA_INSTAGRAM = { id: 3, channel_type: 'Channel::Instagram' };

// #2113: o selo da reação no canto do balão do Direct e o "Reagir" ao lado dele.
const montar = ({
  podeOperar = true,
  podeResponderNaJanela = true,
  messageType = MESSAGE_TYPES.INCOMING,
  contentAttributes = {},
} = {}) => {
  const store = createStore({
    getters: {
      ...gettersDaMontagem,
      'inboxes/getInbox': () => () => CAIXA_INSTAGRAM,
      getSelectedChat: () => ({
        id: 7,
        meta: {},
        can_reply: podeResponderNaJanela,
      }),
      canOperateConversation: () => () => podeOperar,
    },
  });
  return mount(Message, {
    props: {
      id: 1,
      messageType,
      status: MESSAGE_STATUS.SENT,
      content: 'Tem a bolsa em preto?',
      contentAttributes,
      conversationId: 7,
      inboxId: 3,
      sourceId: 'mid.DOCLIENTE',
      createdAt: AGORA,
      currentUserId: 1,
      sender: { id: 2, name: 'Ana', type: 'Contact' },
      inboxSupportsReplyTo: { incoming: false, outgoing: false },
    },
    global: { ...montagem, plugins: [store] },
  });
};

const selo = wrapper => wrapper.find('[data-reacoes-do-instagram]');
const botaoReagir = wrapper =>
  wrapper.find('[aria-label="CONVERSA_CANAL.REAGIR.BOTAO"]');

describe('Reações na linha do Instagram', () => {
  beforeEach(() => {
    ConversaCanalAPI.reagir.mockReset().mockResolvedValue({});
  });

  it('mostra a reação do cliente no selo do canto do balão', () => {
    const wrapper = montar({
      messageType: MESSAGE_TYPES.OUTGOING,
      contentAttributes: {
        reactions: [{ emoji: '❤️', senderType: 'Contact', senderId: 2 }],
      },
    });

    expect(selo(wrapper).exists()).toBe(true);
    expect(selo(wrapper).text()).toBe('❤️');
    expect(selo(wrapper).classes()).toContain('end-2');
  });

  it('mais de uma reação: os emojis e o total', () => {
    const wrapper = montar({
      contentAttributes: {
        reactions: [
          { emoji: '❤️', senderType: 'Contact', senderId: 2 },
          { emoji: '👍', senderType: 'User', senderId: 1 },
        ],
      },
    });

    expect(selo(wrapper).text()).toContain('❤️');
    expect(selo(wrapper).text()).toContain('👍');
    expect(selo(wrapper).text()).toContain('2');
    expect(selo(wrapper).classes()).toContain('start-2');
  });

  it('mensagem traduzida: o selo fica no balão e o "Ver original" embaixo, fora dele', () => {
    const wrapper = montar({
      contentAttributes: {
        translations: { pt_BR: 'Você tem a bolsa em preto?' },
        reactions: [{ emoji: '❤️', senderType: 'User', senderId: 1 }],
      },
    });
    const baloes = wrapper.find('[data-baloes-do-instagram]');

    expect(baloes.classes()).toContain('relative');
    expect(baloes.find('[data-reacoes-do-instagram]').exists()).toBe(true);
    expect(baloes.text()).not.toContain('VIEW_ORIGINAL');
    expect(baloes.element.nextElementSibling.textContent).toContain(
      'VIEW_ORIGINAL'
    );
  });

  it('sem reação, sem selo', () => {
    expect(selo(montar()).exists()).toBe(false);
  });

  it('quem opera vê o Reagir na mensagem do cliente e a reação vai ao servidor', async () => {
    const wrapper = montar();

    expect(botaoReagir(wrapper).exists()).toBe(true);
    await botaoReagir(wrapper).trigger('click');
    await wrapper
      .find('[aria-label="CONVERSA_CANAL.REAGIR.COM"]')
      .trigger('click');
    await flushPromises();

    expect(ConversaCanalAPI.reagir).toHaveBeenCalledWith(7, 1, '👍');
  });

  it('quem só lê a conversa não vê o Reagir', () => {
    expect(botaoReagir(montar({ podeOperar: false })).exists()).toBe(false);
  });

  it('nossa mensagem não tem Reagir (a Meta só reage à do cliente)', () => {
    const wrapper = montar({ messageType: MESSAGE_TYPES.OUTGOING });

    expect(botaoReagir(wrapper).exists()).toBe(false);
  });

  it('fora da janela, o Reagir fica bloqueado e não manda nada', async () => {
    const wrapper = montar({ podeResponderNaJanela: false });

    expect(botaoReagir(wrapper).attributes('aria-disabled')).toBe('true');
    await botaoReagir(wrapper).trigger('click');

    expect(wrapper.find('[role="toolbar"]').exists()).toBe(false);
    expect(ConversaCanalAPI.reagir).not.toHaveBeenCalled();
  });
});
