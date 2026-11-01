import { flushPromises, mount, enableAutoUnmount } from '@vue/test-utils';
import { ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import { fetchContactableInboxes } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import { useAlert } from 'dashboard/composables';
import ConversaVazia from '../ConversaVazia.vue';
import { criarI18n } from '../../specs/apoio';

// #2211 (revisão) — telefone novo com o useNovaConversa DE VERDADE (sem simular): o envio pelo
// modelo do Twilio cria o contato antes, e a caixa que muda de tipo depois de criado o contato
// (Híbrido: o servidor decide modelo ou texto livre por contato) avisa e não envia nada calado.
const estado = vi.hoisted(() => ({ dispatch: null, caixasDaConta: [] }));

vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => false }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ fetchSignatureFlagFromUISettings: () => false }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: (...args) => estado.dispatch(...args) }),
  useMapGetter: nome => {
    const getters = {
      getCurrentUser: { id: 3 },
      'globalConfig/get': { directUploadsEnabled: false },
      getMessageSignature: '',
      getCurrentAccountId: 1,
      'inboxes/getInboxes': estado.caixasDaConta,
      'inboxes/getInbox': () => null,
      'accounts/isFeatureEnabledonAccount': () => false,
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { show: vi.fn(), create: vi.fn() },
}));
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  async importOriginal => ({
    ...(await importOriginal()),
    fetchContactableInboxes: vi.fn(),
  })
);
vi.mock(
  'dashboard/components-next/NovaConversa/useNovaConversaContato',
  () => ({
    useNovaConversaContato: () => ({
      contato: ref(null),
      canais: ref([]),
      carregandoCanais: ref(false),
      erroNosCanais: ref(false),
      escolherContato: vi.fn(),
    }),
  })
);
// Conversa nova (não continua nenhuma).
vi.mock('dashboard/components-next/NovaConversa/useContinuarConversa', () => ({
  useContinuarConversa: () => ({
    esperando: ref(false),
    conversa: ref(null),
    oculta: ref(false),
    tipo: ref(''),
    assunto: ref(''),
    ultimoEmail: ref(null),
    meta: ref(null),
    carregar: vi.fn(),
  }),
}));
// A caixa de resposta mostra o tipo e o texto que recebe; os botões fazem o que a pessoa faz.
vi.mock('../CaixaDaConversaVazia.vue', () => ({
  default: {
    props: ['canal', 'tipo', 'mensagem', 'modelo'],
    emits: [
      'enviar',
      'enviarPronta',
      'update:mensagem',
      'update:modelo',
      'update:camposProntos',
    ],
    template: `<div data-caixa :data-tipo="tipo" :data-mensagem="mensagem">
      <button data-escrever @click="$emit('update:mensagem', 'Olá, tudo bem?')" />
      <button data-escolher-modelo @click="$emit('update:modelo', { name: 'boas_vindas' }); $emit('update:camposProntos', true)" />
      <button data-enviar @click="$emit('enviar')" />
      <button data-enviar-pronta @click="$emit('enviarPronta', { message: 'Olá do modelo', templateParams: { name: 'boas_vindas' } })" />
    </div>`,
    methods: {
      montar: () => ({
        message: 'Olá do modelo',
        templateParams: { name: 'boas_vindas' },
      }),
    },
  },
}));

enableAutoUnmount(afterEach);

const TELEFONE = '+5511955557777';
const CRIADO = {
  data: { payload: { contact: { id: 77, name: '+55 11 95555-7777' } } },
};
const montar = async (caixasLivres = []) => {
  const wrapper = mount(ConversaVazia, {
    // A busca disse que dá para começar em todas as caixas da conta (caixas_para_comecar).
    props: {
      telefone: TELEFONE,
      caixasLivres,
      caixasPermitidas: estado.caixasDaConta.map(caixa => String(caixa.id)),
    },
    global: {
      plugins: [criarI18n()],
      stubs: { RouterLink: { template: '<a><slot /></a>' } },
    },
  });
  await flushPromises();
  return wrapper;
};
const criacoes = () =>
  estado.dispatch.mock.calls.filter(
    ([acao]) => acao === 'contactConversations/create'
  );

describe('ConversaVazia com o useNovaConversa de verdade', () => {
  beforeEach(() => {
    estado.dispatch = vi.fn(async acao =>
      acao === 'contactConversations/create'
        ? { id: 42, account_id: 1 }
        : undefined
    );
    useAlert.mockReset();
    ContactAPI.create.mockReset();
    fetchContactableInboxes.mockReset();
    ContactAPI.create.mockResolvedValue(CRIADO);
  });

  it('Twilio: o modelo pronto sai para o contato criado antes, com a caixa que o servidor devolveu', async () => {
    estado.caixasDaConta.splice(0, Infinity, {
      id: 6,
      name: 'Twilio WhatsApp',
      channel_type: 'Channel::TwilioSms',
      medium: 'whatsapp',
    });
    fetchContactableInboxes.mockResolvedValue([
      {
        id: 6,
        name: 'Twilio WhatsApp',
        channelType: 'Channel::TwilioSms',
        medium: 'whatsapp',
        sourceId: `whatsapp:${TELEFONE}`,
      },
    ]);
    const wrapper = await montar();
    expect(wrapper.find('[data-caixa]').attributes('data-tipo')).toBe(
      'whatsapp_twilio'
    );

    await wrapper.find('[data-enviar-pronta]').trigger('click');
    await flushPromises();

    expect(ContactAPI.create).toHaveBeenCalledTimes(1);
    expect(criacoes()).toHaveLength(1);
    expect(criacoes()[0][1].params).toMatchObject({
      inboxId: 6,
      contactId: 77,
      sourceId: `whatsapp:${TELEFONE}`,
      message: { content: 'Olá do modelo' },
    });
  });

  it('Híbrido com a caixa na lista do servidor (#2257): já começa no texto livre e envia de primeira', async () => {
    estado.caixasDaConta.splice(0, Infinity, {
      id: 1,
      name: 'WhatsApp Oficial',
      channel_type: 'Channel::Whatsapp',
    });
    fetchContactableInboxes.mockResolvedValue([
      {
        id: 1,
        name: 'WhatsApp Oficial',
        channelType: 'Channel::Whatsapp',
        sourceId: '5511955557777',
        whatsappApiStart: true,
      },
    ]);
    const wrapper = await montar(['1']);
    expect(wrapper.find('[data-caixa]').attributes('data-tipo')).toBe(
      'whatsapp_livre'
    );
    await wrapper.find('[data-escrever]').trigger('click');
    await wrapper.find('[data-enviar]').trigger('click');
    await flushPromises();
    expect(useAlert).not.toHaveBeenCalled();
    expect(criacoes()).toHaveLength(1);
    expect(criacoes()[0][1].params).toMatchObject({
      inboxId: 1,
      contactId: 77,
      message: { content: 'Olá, tudo bem?' },
    });
  });

  it('rede de segurança: a busca disse texto livre, mas no envio o servidor pede modelo — avisa e não envia', async () => {
    estado.caixasDaConta.splice(0, Infinity, {
      id: 1,
      name: 'WhatsApp Oficial',
      channel_type: 'Channel::Whatsapp',
    });
    // A trava de tempo do Híbrido fechou entre a busca e o envio.
    fetchContactableInboxes.mockResolvedValue([
      {
        id: 1,
        name: 'WhatsApp Oficial',
        channelType: 'Channel::Whatsapp',
        sourceId: '5511955557777',
        whatsappApiStart: false,
      },
    ]);
    const wrapper = await montar(['1']);
    await wrapper.find('[data-escrever]').trigger('click');
    await wrapper.find('[data-enviar]').trigger('click');
    await flushPromises();
    // O texto não aparece na escolha do modelo: o aviso não promete que ele ficou.
    expect(useAlert).toHaveBeenCalledWith(
      'Este número precisa de uma mensagem aprovada agora. Escolha uma para começar.'
    );
    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(criacoes()).toHaveLength(0);
    const caixa = wrapper.find('[data-caixa]');
    expect(caixa.attributes('data-tipo')).toBe('whatsapp_pronta');
    expect(caixa.attributes('data-mensagem')).toBe('Olá, tudo bem?');
  });

  it('rede de segurança, ao contrário: sem a caixa na lista, o servidor libera o texto livre no envio — avisa, não envia, o texto fica; o segundo Enviar manda', async () => {
    // Sem a caixa na lista da busca, a tela começa no modelo.
    estado.caixasDaConta.splice(0, Infinity, {
      id: 1,
      name: 'WhatsApp Oficial',
      channel_type: 'Channel::Whatsapp',
    });
    // Para o contato criado, o servidor libera o texto livre (whatsapp_api_start).
    fetchContactableInboxes.mockResolvedValue([
      {
        id: 1,
        name: 'WhatsApp Oficial',
        channelType: 'Channel::Whatsapp',
        sourceId: '5511955557777',
        whatsappApiStart: true,
      },
    ]);
    const wrapper = await montar();
    expect(wrapper.find('[data-caixa]').attributes('data-tipo')).toBe(
      'whatsapp_pronta'
    );
    await wrapper.find('[data-escrever]').trigger('click');
    await wrapper.find('[data-escolher-modelo]').trigger('click');

    await wrapper.find('[data-enviar]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Esta caixa mudou o que dá para mandar primeiro. Confira a mensagem e envie de novo: o que você escreveu ficou.'
    );
    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(criacoes()).toHaveLength(0);
    const caixa = wrapper.find('[data-caixa]');
    expect(caixa.attributes('data-tipo')).toBe('whatsapp_livre');
    expect(caixa.attributes('data-mensagem')).toBe('Olá, tudo bem?');

    await wrapper.find('[data-enviar]').trigger('click');
    await flushPromises();
    expect(ContactAPI.create).toHaveBeenCalledTimes(1);
    expect(fetchContactableInboxes).toHaveBeenCalledTimes(1);
    expect(criacoes()).toHaveLength(1);
    expect(criacoes()[0][1].params).toMatchObject({
      inboxId: 1,
      contactId: 77,
      message: { content: 'Olá, tudo bem?' },
    });
  });

  it('mesmo tipo antes e depois: envia de primeira, sem aviso', async () => {
    estado.caixasDaConta.splice(0, Infinity, {
      id: 1,
      name: 'WhatsApp Oficial',
      channel_type: 'Channel::Whatsapp',
    });
    fetchContactableInboxes.mockResolvedValue([
      {
        id: 1,
        name: 'WhatsApp Oficial',
        channelType: 'Channel::Whatsapp',
        sourceId: '5511955557777',
      },
    ]);
    const wrapper = await montar();
    await wrapper.find('[data-escolher-modelo]').trigger('click');
    await wrapper.find('[data-enviar]').trigger('click');
    await flushPromises();
    expect(useAlert).not.toHaveBeenCalled();
    expect(criacoes()).toHaveLength(1);
    expect(criacoes()[0][1].params).toMatchObject({
      contactId: 77,
      message: {
        content: 'Olá do modelo',
        template_params: { name: 'boas_vindas' },
      },
    });
  });
});
