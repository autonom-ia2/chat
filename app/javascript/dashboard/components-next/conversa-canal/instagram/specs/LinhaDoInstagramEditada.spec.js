import { computed } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
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
vi.mock('../useConversaDoInstagram', async original => ({
  ...(await original()),
  useInstagramDaConversa: () => ({
    ligado: computed(() => true),
    fuso: computed(() => undefined),
    contato: computed(() => null),
  }),
  useSequenciaDoInstagram: () => computed(() => new Map()),
}));

// Monta a mensagem do Instagram como na conversa (mesmo preparo do spec do Responder).
const montar = ({
  podeOperar = true,
  // A caixa do Instagram de hoje não responde a uma mensagem (INBOX_FEATURE_MAP, useInbox.js).
  canalResponde = false,
  content = 'Tem a bolsa em preto?',
  contentAttributes = {},
} = {}) => {
  const store = createStore({
    getters: {
      ...gettersDaMontagem,
      getSelectedChat: () => ({ id: 7, meta: {} }),
      canOperateConversation: () => () => podeOperar,
    },
  });
  return mount(Message, {
    props: {
      id: 1,
      messageType: MESSAGE_TYPES.INCOMING,
      status: MESSAGE_STATUS.SENT,
      content,
      contentAttributes,
      conversationId: 7,
      createdAt: AGORA,
      currentUserId: 1,
      sender: { id: 2, name: 'Cliente', type: 'Contact' },
      inboxSupportsReplyTo: {
        incoming: canalResponde,
        outgoing: canalResponde,
      },
    },
    global: { ...montagem, plugins: [store] },
  });
};

const EDITADA = {
  editedAt: '2026-10-23T12:00:00Z',
  editHistory: [
    {
      content: 'Tem a bolsa em preto?',
      editedAt: '2026-10-23T12:00:00Z',
      senderType: 'Contact',
    },
  ],
};

const rotulo = wrapper => wrapper.find('[data-editada-do-instagram]');

// #2113: o cliente editou a mensagem no Instagram; o balão mostra o texto novo e "Editada".
describe('Editada na linha do Instagram', () => {
  it('mensagem editada mostra o texto atual e o "Editada"', () => {
    const wrapper = montar({
      content: 'Tem a bolsa em marrom?',
      contentAttributes: EDITADA,
    });

    expect(wrapper.findComponent({ name: 'LinhaDoInstagram' }).exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('Tem a bolsa em marrom?');
    expect(rotulo(wrapper).exists()).toBe(true);
    expect(rotulo(wrapper).text()).toBe('CONVERSA_CANAL.EDITADA.ROTULO');
  });

  it('clicar no "Editada" mostra a versão anterior, aberta pelo início na recebida', async () => {
    const wrapper = montar({
      content: 'Tem a bolsa em marrom?',
      contentAttributes: EDITADA,
    });

    await wrapper.find('[data-rotulo-editada]').trigger('click');

    const versoes = wrapper.find('[data-versoes-anteriores]');
    expect(versoes.exists()).toBe(true);
    expect(versoes.text()).toContain('Tem a bolsa em preto?');
    expect(versoes.classes()).toContain('ltr:left-0');
  });

  it('mensagem sem edição não mostra o "Editada"', () => {
    const wrapper = montar();

    expect(rotulo(wrapper).exists()).toBe(false);
  });

  it('mensagem apagada pelo cliente não mostra o "Editada"', () => {
    const wrapper = montar({
      content: 'Esta mensagem foi apagada',
      contentAttributes: { ...EDITADA, deleted: true },
    });

    expect(rotulo(wrapper).exists()).toBe(false);
  });
});
