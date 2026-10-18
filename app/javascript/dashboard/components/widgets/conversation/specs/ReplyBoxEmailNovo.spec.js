import { computed, nextTick } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import ReplyBox from '../ReplyBox.vue';

// #1786 — a resposta da conversa de e-mail nova no ReplyBox: o que é de uma conversa
// não passa para outra, e o envio trava quando iria para o lugar errado.
const api = vi.hoisted(() => ({ abrir: vi.fn() }));
vi.mock('dashboard/api/modelosDeEmail', () => ({ default: api }));
vi.mock(
  'dashboard/components-next/conversa-canal/email/modeloDeEmail',
  async original => ({
    ...(await original()),
    montarModelo: vi.fn(async ({ html }) => html),
  })
);
vi.mock(
  'dashboard/components-next/conversa-canal/email/useConversaDeEmail',
  async original => ({
    ...(await original()),
    useEmailDaConversa: () => ({
      ligado: computed(() => true),
      fecharResposta: () => {},
    }),
  })
);

const EMAIL = { channel_type: 'Channel::Email', email: 'loja@exemplo.com' };
const conversa = (id, email) => ({
  id,
  inbox_id: 1,
  can_reply: true,
  status: 'open',
  meta: { sender: { id: id + 100, email, name: 'Cliente' } },
  messages: [],
});
const ultimoEmail = (id, de) => ({
  id,
  message_type: 0,
  content_attributes: { email: { from: [de], to: ['loja@exemplo.com'] } },
});

const montar = () => {
  const store = createStore({
    state: {
      chat: conversa(1, 'marina@exemplo.com'),
      ultimo: ultimoEmail(10, 'marina@exemplo.com'),
      mode: REPLY_EDITOR_MODES.REPLY,
    },
    mutations: {
      chat: (s, c) => {
        s.chat = c;
      },
      ultimo: (s, m) => {
        s.ultimo = m;
      },
      mode: (s, m) => {
        s.mode = m;
      },
    },
    actions: {
      'draftMessages/setReplyEditorMode': ({ commit }, { mode }) =>
        commit('mode', mode),
      'draftMessages/set': () => {},
    },
    getters: {
      getSelectedChat: s => s.chat,
      getCurrentUser: () => ({ id: 7, name: 'Agente', accounts: [] }),
      getCurrentAccountId: () => 1,
      getMessageSignature: () => '',
      getUISettings: () => ({}),
      getLastEmailInSelectedChat: s => s.ultimo,
      'globalConfig/get': () => ({}),
      'globalConfig/isMetaMessageSendingDisabled': () => false,
      'inboxes/getInbox': () => id => ({ id, ...EMAIL }),
      'inboxes/getWhatsAppTemplates': () => () => [],
      'contacts/getContact': () => () => ({}),
      'draftMessages/get': () => () => '',
      'draftMessages/getReplyEditorMode': s => s.mode,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'accounts/getAccount': () => () => ({}),
      'portals/allPortals': () => [],
      'integrations/getUIFlags': () => ({ isFetching: false }),
    },
  });
  const wrapper = shallowMount(ReplyBox, {
    global: {
      plugins: [store],
      mocks: { $t: chave => chave },
      stubs: {
        transition: false,
        // O ReplyBox foca o editor num requestAnimationFrame depois de abrir a resposta;
        // o stub raso não teria o método e o erro estouraria depois do teste.
        WootMessageEditor: {
          template: '<div />',
          methods: { focusEditorInputField: vi.fn() },
        },
      },
    },
  });
  return { wrapper, store };
};

describe('ReplyBox na conversa de e-mail nova', () => {
  beforeEach(() => api.abrir.mockReset());

  it('trocar de conversa zera o modelo, a citação e o tipo da resposta', async () => {
    const { wrapper, store } = montar();
    await wrapper.setData({
      modeloDoEmail: { id: 3, nome: 'Proposta', html: '<p>Olá Marina</p>' },
      valoresDoModelo: { nome: 'Marina' },
      citacaoDoEmail: { tipo: 'encaminhado', mensagemId: 10 },
      modoDoEmail: 'encaminhar',
      historicoDesligado: true,
    });

    store.commit('chat', conversa(2, 'joao@exemplo.com'));
    await nextTick();

    expect(wrapper.vm.modeloDoEmail).toBeNull();
    expect(wrapper.vm.valoresDoModelo).toEqual({});
    expect(wrapper.vm.citacaoDoEmail).toBeNull();
    expect(wrapper.vm.modoDoEmail).toBe('todos');
    expect(wrapper.vm.historicoDesligado).toBe(false);
  });

  it('o modelo que chega depois de trocar de conversa é descartado', async () => {
    let entregar;
    api.abrir.mockReturnValue(
      new Promise(resolve => {
        entregar = resolve;
      })
    );
    const { wrapper, store } = montar();

    const pedido = wrapper.vm.carregarModeloDeCampanha(3);
    store.commit('chat', conversa(2, 'joao@exemplo.com'));
    await nextTick();
    entregar({
      data: { id: 3, nome: 'Proposta', html: '<p>Olá Marina</p>', campos: [] },
    });
    await pedido;

    expect(wrapper.vm.modeloDoEmail).toBeNull();
  });

  it('e-mail novo do cliente no meio da resposta não troca o Para', async () => {
    const { wrapper, store } = montar();
    wrapper.vm.responderEmail({ modo: 'encaminhar', mensagemId: 10 });
    await wrapper.setData({ toEmails: 'juridico@loja.com' });

    store.commit('ultimo', ultimoEmail(11, 'marina@exemplo.com'));
    await flushPromises();

    expect(wrapper.vm.toEmails).toBe('juridico@loja.com');
  });

  it('Encaminhar sem Para ou com endereço errado trava o envio', async () => {
    const { wrapper } = montar();
    wrapper.vm.responderEmail({ modo: 'encaminhar', mensagemId: 10 });
    await wrapper.setData({ message: 'Segue para análise' });
    expect(wrapper.vm.toEmails).toBe('');
    expect(wrapper.vm.isReplyButtonDisabled).toBe(true);

    await wrapper.setData({ toEmails: 'juridico@loja' });
    expect(wrapper.vm.isReplyButtonDisabled).toBe(true);

    await wrapper.setData({ toEmails: 'juridico@loja.com' });
    expect(wrapper.vm.isReplyButtonDisabled).toBe(false);
  });

  it('trocar o tipo pelo topo continua no mesmo e-mail e mantém o Cc posto à mão', async () => {
    const { wrapper } = montar();
    wrapper.vm.responderEmail({ modo: 'responder', mensagemId: 10 });
    await wrapper.setData({ ccEmails: 'gerente@loja.com' });

    wrapper.vm.trocarTipoDoEmail('todos');

    expect(wrapper.vm.ccEmails).toBe('gerente@loja.com');
    expect(wrapper.vm.citacaoDoEmail).toEqual({
      tipo: 'historico',
      mensagemId: 10,
    });
  });
});
