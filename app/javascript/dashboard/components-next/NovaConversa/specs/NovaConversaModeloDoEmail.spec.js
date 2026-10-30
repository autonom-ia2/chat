import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { createConversationPayload } from 'dashboard/store/modules/contactConversations';
import NovaConversaGaveta from '../NovaConversaGaveta.vue';

// #1809 — o "Modelo de e-mail" do "+" na gaveta "Escrever": abre pelo "+", preenche
// pelo contato escolhido (sem conversa), o campo sem fonte vem vazio e destacado, a
// prévia mostra o modelo e o envio leva o `email_modelo`, como na resposta.
const estado = vi.hoisted(() => ({
  dispatch: null,
  chave: true,
  listar: vi.fn(),
  abrir: vi.fn(),
  abrirParaContato: vi.fn(),
  previa: vi.fn(),
  alerta: vi.fn(),
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
vi.mock('dashboard/composables', () => ({ useAlert: estado.alerta }));
vi.mock('dashboard/api/modelosDeEmail', () => ({
  default: {
    listar: estado.listar,
    abrir: estado.abrir,
    abrirParaContato: estado.abrirParaContato,
    previa: estado.previa,
  },
}));
vi.mock('dashboard/api/conversaEmail', () => ({
  default: { ditadoDisponivel: vi.fn(async () => ({ data: {} })) },
}));
// O compilador de MJML (GrapesJS) não entra no teste: o modelo vem em HTML.
vi.mock('dashboard/helper/compileEmailMjml', () => ({
  compileEmailMjml: async () => '',
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
};
const HTML =
  '<html><head></head><body><p>Olá, {{ nome }}! Cotação {{ numero_da_cotacao }}.</p>' +
  '<div class="footer-locked">Sair da lista</div></body></html>';
const DO_SERVIDOR = {
  id: 77,
  nome: 'Proposta',
  mjml: null,
  html: HTML,
  campos: [
    { chave: 'nome', valor: 'Marina Costa', origem: 'contato' },
    { chave: 'numero_da_cotacao', valor: '', origem: 'vazio' },
  ],
};

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
        // O editor do e-mail: um campo simples, com o mesmo v-model.
        WootEditor: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template: `<textarea data-editor :value="modelValue"
            @input="$emit('update:modelValue', $event.target.value)" />`,
        },
        // A janela de modelos é um <dialog>; aqui, sempre aberta.
        Dialog: {
          template: '<div data-dialogo><slot /></div>',
          methods: { open() {}, close() {} },
        },
      },
    },
  });
  await wrapper.find('[data-abrir]').trigger('click');
  await flushPromises();
  return wrapper;
};

const escolherPeloMais = async wrapper => {
  await wrapper.find('[data-mais-do-email]').trigger('click');
  await wrapper.find('[data-item-do-mais="modelo"]').trigger('click');
  await wrapper.find('[data-modelo-de-email="77"]').trigger('click');
  await flushPromises();
};

const criou = () =>
  estado.dispatch.mock.calls.find(
    ([acao]) => acao === 'contactConversations/create'
  );

describe('Modelo de e-mail na gaveta "Escrever" (#1809)', () => {
  beforeEach(() => {
    estado.chave = true;
    estado.canais = [EMAIL];
    estado.dispatch = vi.fn(async acao =>
      acao === 'contactConversations/create' ? { id: 42, account_id: 7 } : null
    );
    estado.listar
      .mockReset()
      .mockResolvedValue({ data: { payload: [{ id: 77, nome: 'Proposta' }] } });
    estado.abrir.mockReset();
    estado.abrirParaContato
      .mockReset()
      .mockResolvedValue({ data: DO_SERVIDOR });
    estado.previa.mockReset().mockResolvedValue({ data: { html: HTML } });
    estado.alerta.mockReset();
  });

  it('o "+" oferece "Modelo de e-mail" e preenche pelo contato escolhido, sem conversa', async () => {
    const wrapper = await abrir();
    await escolherPeloMais(wrapper);

    expect(estado.abrirParaContato).toHaveBeenCalledWith(77, {
      contactId: 9,
      inboxId: 4,
    });
    expect(estado.abrir).not.toHaveBeenCalled();
    const modelo = wrapper.find('[data-modelo-da-resposta]');
    expect(modelo.exists()).toBe(true);
    expect(modelo.find('[data-campo-do-modelo="nome"]').element.value).toBe(
      'Marina Costa'
    );
  });

  it('o campo sem fonte vem vazio, destacado e com o selo "preencha"', async () => {
    const wrapper = await abrir();
    await escolherPeloMais(wrapper);

    const vazio = wrapper.find('[data-campo-do-modelo="numero_da_cotacao"]');
    expect(vazio.element.value).toBe('');
    expect(vazio.classes()).toContain('border-n-amber-7');
    expect(vazio.element.closest('label').textContent).toContain(
      'CONVERSA_CANAL.EMAIL.PREENCHA'
    );
    const cheio = wrapper.find('[data-campo-do-modelo="nome"]');
    expect(cheio.classes()).not.toContain('border-n-amber-7');
  });

  it('a prévia "Como X recebe" mostra o modelo, com o vazio marcado', async () => {
    const wrapper = await abrir();
    await escolherPeloMais(wrapper);

    const previa = wrapper.find('[data-previa-do-modelo-na-gaveta]');
    expect(previa.exists()).toBe(true);
    expect(previa.attributes('srcdoc')).toContain('Marina Costa');
    expect(previa.attributes('srcdoc')).toContain('<mark');
    expect(previa.attributes('srcdoc')).not.toContain('Sair da lista');
  });

  it('o envio cria a conversa com o texto, o assunto e o email_modelo preenchido', async () => {
    const wrapper = await abrir();
    await wrapper.find('#nova-conversa-assunto').setValue('Sua proposta');
    await wrapper.find('[data-editor]').setValue('Segue a proposta.');
    await escolherPeloMais(wrapper);
    await wrapper
      .find('[data-campo-do-modelo="numero_da_cotacao"]')
      .setValue('COT-4817');

    await wrapper.find('[data-nova-conversa-principal]').trigger('click');
    await flushPromises();

    const { params } = criou()[1];
    expect(params.mailSubject).toBe('Sua proposta');
    expect(params.message.content).toBe('Segue a proposta.');
    const { email_modelo: pedido, email_citacao: citacao } =
      params.message.content_attributes;
    expect(pedido.template_id).toBe(77);
    expect(pedido.so_modelo).toBe(false);
    expect(pedido.html).toContain('Olá, Marina Costa! Cotação COT-4817.');
    expect(pedido.html).not.toContain('Sair da lista');
    expect(pedido.html).not.toContain('<mark');
    expect(citacao).toBeUndefined();

    // O FormData da criação leva o pedido ao MessageBuilder.
    const formulario = createConversationPayload({ params, contactId: 9 });
    expect(
      JSON.parse(formulario.get('message[content_attributes]')).email_modelo
        .template_id
    ).toBe(77);
  });

  it('com campo vazio, envia igual (como a resposta: só destaca)', async () => {
    const wrapper = await abrir();
    await wrapper.find('#nova-conversa-assunto').setValue('Sua proposta');
    await escolherPeloMais(wrapper);

    await wrapper.find('[data-nova-conversa-principal]').trigger('click');
    await flushPromises();

    const { params } = criou()[1];
    const pedido = params.message.content_attributes.email_modelo;
    // Sem texto do atendente: sai só o modelo, e o conteúdo é o texto dele.
    expect(pedido.so_modelo).toBe(true);
    expect(params.message.content).toContain('Olá, Marina Costa!');
  });

  it('"Tirar" o modelo volta ao envio de antes, sem email_modelo', async () => {
    const wrapper = await abrir();
    await wrapper.find('#nova-conversa-assunto').setValue('Sua proposta');
    await wrapper.find('[data-editor]').setValue('Oi');
    await escolherPeloMais(wrapper);
    await wrapper.find('[data-tirar-modelo]').trigger('click');

    await wrapper.find('[data-nova-conversa-principal]').trigger('click');
    await flushPromises();

    expect(criou()[1].params.message.content_attributes).toBeUndefined();
  });

  it('sem a chave conversa_email_nova, não há "+" nem modelo', async () => {
    estado.chave = false;
    const wrapper = await abrir();
    expect(wrapper.find('[data-mais-do-email]').exists()).toBe(false);
    expect(estado.listar).not.toHaveBeenCalled();
  });
});
