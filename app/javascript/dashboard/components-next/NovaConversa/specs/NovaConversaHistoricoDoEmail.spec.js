import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import NovaConversaGaveta from '../NovaConversaGaveta.vue';

// #1809 — continuar uma conversa de e-mail pela gaveta (#1505): o histórico vai junto,
// como na resposta (CitacaoDaResposta e "Não enviar o histórico"), com ou sem modelo; e
// o assunto é o da conversa, com "Re: ", na prévia e na confirmação.
const estado = vi.hoisted(() => ({
  dispatch: null,
  chave: true,
  show: vi.fn(),
  mensagens: vi.fn(),
  canais: [],
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, dados) => (dados?.nome ? `${chave}:${dados.nome}` : chave),
  }),
  // O título da gaveta põe o nome por slot (#2255).
  I18nT: {
    props: ['keypath'],
    template: '<span>{{ keypath }}:<slot name="nome" /></span>',
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home', params: { accountId: 7 } }),
  useRouter: () => ({ push: vi.fn(), hasRoute: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
  useMapGetter: nome => {
    const getters = {
      'inboxes/getInboxes': [],
      'contacts/getContactById': id => ({
        id: Number(id),
        name: 'Marina Costa',
        email: 'marina@exemplo.com.br',
      }),
      'inboxes/getConversationWhatsAppTemplates': () => [],
      'inboxes/getInbox': id =>
        id === 4 ? { channel_type: INBOX_TYPES.EMAIL } : {},
      'accounts/isRTL': false,
      getCurrentUser: { id: 3 },
      getCurrentAccountId: 7,
      'accounts/isFeatureEnabledonAccount': (_conta, flag) =>
        flag === 'conversa_email_nova' && estado.chave,
      'globalConfig/get': { directUploadsEnabled: false },
      getMessageSignature: '',
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/helper/permissionsHelper.js', () => ({
  getUserPermissions: () => ['agent'],
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    fetchSignatureFlagFromUISettings: () => false,
    setSignatureFlagForInbox: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('dashboard/composables/useFileUpload', () => ({
  useFileUpload: () => ({ onFileUpload: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/modelosDeEmail', () => ({
  default: { listar: vi.fn(async () => ({ data: { payload: [] } })) },
}));
vi.mock('dashboard/api/conversaEmail', () => ({
  default: { ditadoDisponivel: vi.fn(async () => ({ data: {} })) },
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { show: (...args) => estado.show(...args) },
}));
vi.mock('dashboard/api/inbox/message', () => ({
  default: { getPreviousMessages: (...args) => estado.mensagens(...args) },
}));
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  async original => ({
    ...(await original()),
    fetchContactableInboxes: vi.fn(async () => estado.canais),
    createContactSearcher: () => vi.fn(async () => []),
  })
);

const EMAIL = {
  id: 4,
  name: 'Comercial',
  channelType: INBOX_TYPES.EMAIL,
  email: 'comercial@loja.com',
  sourceId: 's4',
  conversationToContinue: {
    id: 610,
    displayId: 61,
    status: 'open',
    lastActivityAt: Math.floor(Date.now() / 1000) - 60,
    locked: false,
    visible: true,
  },
};
const ORIGINAL = {
  id: 300,
  message_type: 0,
  private: false,
  content: 'Pedido original',
  content_attributes: {
    email: { text_content: { full: 'Quero a cotação do seguro.' } },
  },
  sender: { name: 'Marina Costa' },
};
const NOTA = { id: 301, message_type: 1, private: true, content: 'nota' };

const abrir = async () => {
  const wrapper = mount(NovaConversaGaveta, {
    props: { contactId: '9' },
    slots: { trigger: '<button data-abrir>Escrever</button>' },
    attachTo: document.body,
    global: {
      mocks: {
        $t: (chave, dados) => (dados?.nome ? `${chave}:${dados.nome}` : chave),
      },
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        transition: true,
        Icon: true,
        Avatar: true,
        Letter: true,
        WootEditor: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template: `<textarea data-editor :value="modelValue"
            @input="$emit('update:modelValue', $event.target.value)" />`,
        },
      },
    },
  });
  await wrapper.find('[data-abrir]').trigger('click');
  await flushPromises();
  return wrapper;
};

const respondeu = () =>
  estado.dispatch.mock.calls.find(([acao]) => acao === 'sendMessageWithData');
const assuntoDaPrevia = wrapper =>
  wrapper.find('aside [data-nova-conversa-email-assunto]').text();

describe('Histórico e assunto ao continuar um e-mail pela gaveta (#1809)', () => {
  beforeEach(() => {
    estado.chave = true;
    estado.canais = [EMAIL];
    estado.dispatch = vi.fn(async () => null);
    estado.show.mockReset().mockResolvedValue({
      data: {
        can_reply: true,
        additional_attributes: { mail_subject: 'Proposta de seguro' },
      },
    });
    estado.mensagens
      .mockReset()
      .mockResolvedValue({ data: { payload: [ORIGINAL, NOTA] } });
  });

  it('mostra o bloco do histórico do último e-mail (não a nota), ligado por padrão', async () => {
    const wrapper = await abrir();

    expect(estado.mensagens).toHaveBeenCalledWith({ conversationId: 61 });
    const bloco = wrapper.find('[data-citacao-da-resposta="historico"]');
    expect(bloco.exists()).toBe(true);
    expect(bloco.attributes('data-desligado')).toBeUndefined();
    expect(bloco.text()).toContain('CONVERSA_CANAL.EMAIL.HISTORICO_VAI');
  });

  it('a prévia mostra "Re: <assunto da conversa>" e o histórico no fim', async () => {
    const wrapper = await abrir();

    expect(assuntoDaPrevia(wrapper)).toBe('Re: Proposta de seguro');
    const historico = wrapper.find('aside [data-previa-do-historico]');
    expect(historico.text()).toContain(
      'NOVA_CONVERSA.PREVIA.HISTORICO:Marina Costa'
    );
    expect(historico.text()).toContain('Quero a cotação do seguro.');
  });

  it('envia com o histórico (email_citacao), mesmo sem modelo', async () => {
    const wrapper = await abrir();
    await wrapper.find('[data-editor]').setValue('Segue a cotação.');
    await wrapper.find('[data-nova-conversa-principal]').trigger('click');
    await flushPromises();

    const [, pendente] = respondeu();
    expect(pendente.conversationId).toBe(61);
    expect(pendente.message).toBe('Segue a cotação.');
    expect(pendente.contentAttributes).toEqual({
      email_citacao: { tipo: 'historico', message_id: 300 },
    });
    // A confirmação fala do assunto que o e-mail levou.
    expect(
      wrapper
        .find('[data-nova-conversa-enviada] [data-nova-conversa-email-assunto]')
        .text()
    ).toBe('Re: Proposta de seguro');
  });

  it('"Não enviar o histórico" tira da prévia e do envio; "Pôr de volta" desfaz', async () => {
    const wrapper = await abrir();
    await wrapper.find('[data-alternar-historico]').trigger('click');

    expect(
      wrapper.find('[data-citacao-da-resposta]').attributes('data-desligado')
    ).toBeDefined();
    expect(wrapper.find('aside [data-previa-do-historico]').exists()).toBe(
      false
    );
    await wrapper.find('[data-editor]').setValue('Sem histórico.');
    await wrapper.find('[data-nova-conversa-principal]').trigger('click');
    await flushPromises();
    expect(respondeu()[1].contentAttributes).toBeUndefined();
  });

  it('começar conversa nova: sem histórico, e o campo Assunto continua', async () => {
    const wrapper = await abrir();
    const nova = wrapper
      .findAll('input[type=radio]')
      .find(opcao => opcao.element.value === 'nova');
    await nova.setValue(true);
    await flushPromises();

    expect(wrapper.find('[data-citacao-da-resposta]').exists()).toBe(false);
    expect(wrapper.find('#nova-conversa-assunto').exists()).toBe(true);
    await wrapper.find('#nova-conversa-assunto').setValue('Outra proposta');
    expect(assuntoDaPrevia(wrapper)).toBe('Outra proposta');
  });

  it('as mensagens não vieram: sem histórico, mas o envio não trava', async () => {
    estado.mensagens.mockReset().mockRejectedValue(new Error('rede'));
    const wrapper = await abrir();

    expect(wrapper.find('[data-citacao-da-resposta]').exists()).toBe(false);
    expect(assuntoDaPrevia(wrapper)).toBe('Re: Proposta de seguro');
    await wrapper.find('[data-editor]').setValue('Segue.');
    await wrapper.find('[data-nova-conversa-principal]').trigger('click');
    await flushPromises();
    expect(respondeu()[1].contentAttributes).toBeUndefined();
  });

  it('depois de enviar, pergunta de novo ao servidor (o próximo cita o que saiu)', async () => {
    const wrapper = await abrir();
    estado.show.mockClear();
    estado.mensagens.mockClear();
    await wrapper.find('[data-editor]').setValue('Segue.');
    await wrapper.find('[data-nova-conversa-principal]').trigger('click');
    await flushPromises();

    expect(estado.show).toHaveBeenCalledWith(61);
    expect(estado.mensagens).toHaveBeenCalledWith({ conversationId: 61 });
  });

  it('tirar o histórico, começar nova e voltar: o histórico volta a ir junto', async () => {
    const wrapper = await abrir();
    await wrapper.find('[data-alternar-historico]').trigger('click');
    const opcao = valor =>
      wrapper.findAll('input[type=radio]').find(o => o.element.value === valor);
    await opcao('nova').setValue(true);
    await opcao('continuar').setValue(true);
    await flushPromises();

    expect(
      wrapper.find('[data-citacao-da-resposta]').attributes('data-desligado')
    ).toBeUndefined();
  });

  it('sem a chave conversa_email_nova: sem histórico e sem buscar as mensagens', async () => {
    estado.chave = false;
    const wrapper = await abrir();

    expect(estado.mensagens).not.toHaveBeenCalled();
    expect(wrapper.find('[data-citacao-da-resposta]').exists()).toBe(false);
    // O assunto da conversa continua certo na prévia (era "Sem assunto").
    expect(assuntoDaPrevia(wrapper)).toBe('Re: Proposta de seguro');
  });
});
