import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import NovaConversaGaveta from '../NovaConversaGaveta.vue';

// #1505 — o contato já tem conversa na caixa: a gaveta continua essa conversa
// (pela regra da caixa) ou começa outra, com o servidor de mentira.
const estado = vi.hoisted(() => ({
  canais: [],
  modelos: [],
  dispatch: null,
  push: null,
  podeResponder: true,
  falhaNaConversa: false,
  show: null,
}));

const traduz = (chave, dados) =>
  dados ? `${chave}:${Object.values(dados).join(',')}` : chave;

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: traduz }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home', params: { accountId: 7 } }),
  useRouter: () => ({ push: estado.push, hasRoute: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
  useMapGetter: nome => {
    const getters = {
      'inboxes/getInboxes': [],
      'contacts/getContactById': id => ({ id: Number(id), name: 'Ana Souza' }),
      'inboxes/getFilteredWhatsAppTemplates': () => estado.modelos,
      'inboxes/getInbox': () => ({}),
      'accounts/isRTL': false,
      getCurrentUser: { id: 3 },
      getCurrentAccountId: 7,
      'accounts/isFeatureEnabledonAccount': () => false,
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
  useUISettings: () => ({ fetchSignatureFlagFromUISettings: () => false }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock('dashboard/composables/useFileUpload', () => ({
  useFileUpload: () => ({ onFileUpload: vi.fn() }),
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { show: (...args) => estado.show(...args) },
}));
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  async original => ({
    ...(await original()),
    fetchContactableInboxes: vi.fn(async () => estado.canais),
  })
);

const UMA_HORA = 60 * 60;
const conversa = (dados = {}) => ({
  id: 610,
  displayId: 61,
  status: 'open',
  lastActivityAt: Math.floor(Date.now() / 1000) - UMA_HORA,
  locked: false,
  ...dados,
});
const SITE = {
  id: 5,
  name: 'Loja',
  channelType: INBOX_TYPES.WEB,
  sourceId: 's5',
};
const SITE_COM_CONVERSA = { ...SITE, conversationToContinue: conversa() };
const SITE_TRAVADO = {
  ...SITE,
  conversationToContinue: conversa({ status: 'resolved', locked: true }),
};
const WHATSAPP = {
  id: 1,
  name: 'Vendas',
  channelType: INBOX_TYPES.WHATSAPP,
  phoneNumber: '+5511999990000',
  sourceId: 's1',
  whatsappApiStart: true,
  conversationToContinue: conversa(),
};
const EMAIL = {
  id: 4,
  name: 'Contato',
  channelType: INBOX_TYPES.EMAIL,
  email: 'oi@loja.com',
  sourceId: 's4',
  conversationToContinue: conversa({ displayId: 77 }),
};
const MODELO = {
  id: 10,
  name: 'boas_vindas',
  language: 'pt_BR',
  category: 'UTILITY',
  components: [{ type: 'BODY', text: 'Oi! Podemos ajudar?' }],
};

const abrir = async () => {
  const wrapper = mount(NovaConversaGaveta, {
    props: { contactId: '9' },
    slots: { trigger: '<button data-abrir>Enviar mensagem</button>' },
    attachTo: document.body,
    global: {
      mocks: { $t: traduz },
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        transition: true,
        FileUpload: { template: '<span><slot /></span>' },
        MessageEditor: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template: `<textarea data-editor :value="modelValue"
            @input="$emit('update:modelValue', $event.target.value)" />`,
        },
        EmailOptions: true,
        Avatar: true,
      },
    },
  });
  await wrapper.find('[data-abrir]').trigger('click');
  await flushPromises();
  return wrapper;
};

const principal = wrapper => wrapper.find('[data-nova-conversa-principal]');
const chamadas = acao =>
  estado.dispatch.mock.calls.filter(([nome]) => nome === acao);
const respondeu = () => chamadas('sendMessageWithData');
const criou = () => chamadas('contactConversations/create');
const continuar = wrapper =>
  wrapper.find('[data-nova-conversa-continuar] input');
const comecar = wrapper => wrapper.find('[data-nova-conversa-comecar] input');
const ONDE = 'NOVA_CONVERSA.ONDE_ENTRA';

describe('NovaConversaGaveta — continuar a conversa', () => {
  beforeEach(() => {
    estado.canais = [SITE_COM_CONVERSA];
    estado.modelos = [];
    estado.podeResponder = true;
    estado.show = vi.fn(async () => ({
      data: { can_reply: estado.podeResponder },
    }));
    estado.dispatch = vi.fn(async acao =>
      acao === 'contactConversations/create' ? { id: 42, account_id: 7 } : null
    );
    estado.push = vi.fn();
  });

  it('sem conversa para continuar, fica como antes e cria a conversa', async () => {
    estado.canais = [SITE];
    const wrapper = await abrir();

    expect(wrapper.find('[data-nova-conversa-onde-entra]').exists()).toBe(
      false
    );
    expect(estado.show).not.toHaveBeenCalled();
    await wrapper.find('#nova-conversa-texto').setValue('Oi');
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(criou()).toHaveLength(1);
    expect(respondeu()).toHaveLength(0);
  });

  it('com "Reabrir a mesma conversa", diz onde entra, sem escolha', async () => {
    estado.canais = [SITE_TRAVADO];
    const wrapper = await abrir();

    const frase = wrapper.find('[data-nova-conversa-entra-na]');
    expect(frase.text()).toContain(`${ONDE}.ENTRA_NA:61`);
    expect(frase.text()).toContain(`${ONDE}.SITUACAO.RESOLVIDA`);
    expect(wrapper.find('input[name="nova-conversa-destino"]').exists()).toBe(
      false
    );
    expect(estado.show).toHaveBeenCalledWith(61);
  });

  it('com "Criar novas conversas", oferece continuar (marcado) ou começar outra', async () => {
    const wrapper = await abrir();

    expect(continuar(wrapper).element.checked).toBe(true);
    expect(comecar(wrapper).element.checked).toBe(false);
    const opcao = wrapper.find('[data-nova-conversa-continuar]');
    expect(opcao.text()).toContain(`${ONDE}.CONTINUAR:61`);
    expect(opcao.text()).toContain(`${ONDE}.SITUACAO.ABERTA`);
    expect(opcao.text()).toContain(`${ONDE}.ULTIMA_ATIVIDADE:`);
    expect(wrapper.find('[data-nova-conversa-entra-na]').exists()).toBe(false);
  });

  it('continuar responde na conversa, sem criar outra, e abre a conversa certa', async () => {
    const wrapper = await abrir();

    await wrapper.find('#nova-conversa-texto').setValue('Oi de novo');
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(criou()).toHaveLength(0);
    const [[, pendente]] = respondeu();
    expect(pendente).toMatchObject({
      conversationId: 61,
      conversation_id: 61,
      message: 'Oi de novo',
      content: 'Oi de novo',
      private: false,
    });
    expect(
      wrapper.find('[data-nova-conversa-enviada-na-conversa]').text()
    ).toBe('NOVA_CONVERSA.ENVIADA.NA_CONVERSA:61');
    await principal(wrapper).trigger('click');
    expect(estado.push).toHaveBeenCalledWith(
      '/app/accounts/7/conversations/61'
    );
  });

  it('"Começar conversa nova" cria a conversa como antes', async () => {
    const wrapper = await abrir();

    await comecar(wrapper).setValue(true);
    await wrapper.find('#nova-conversa-texto').setValue('Outro assunto');
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(respondeu()).toHaveLength(0);
    expect(criou()[0][1].params.message).toEqual({ content: 'Outro assunto' });
  });

  it('a conversa do WhatsApp fora da janela só aceita mensagem pronta', async () => {
    estado.canais = [WHATSAPP];
    estado.modelos = [MODELO];
    estado.podeResponder = false;
    const wrapper = await abrir();

    expect(wrapper.find('#nova-conversa-texto').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'NOVA_CONVERSA.MENSAGEM.SO_PRONTA_CONVERSA'
    );
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(criou()).toHaveLength(0);
    const [[, pendente]] = respondeu();
    expect(pendente.conversationId).toBe(61);
    expect(pendente.templateParams.name).toBe('boas_vindas');
    expect(pendente.message).toBe('Oi! Podemos ajudar?');
  });

  it('a conversa do WhatsApp dentro da janela aceita texto livre', async () => {
    estado.canais = [WHATSAPP];
    estado.modelos = [MODELO];
    const wrapper = await abrir();

    expect(
      wrapper
        .find('input[name="nova-conversa-modo"][value="escrever"]')
        .exists()
    ).toBe(true);
    expect(wrapper.text()).not.toContain(
      'NOVA_CONVERSA.MENSAGEM.SO_PRONTA_CONVERSA'
    );
  });

  it('no e-mail, continua sem pedir assunto e manda as cópias', async () => {
    estado.canais = [EMAIL];
    const wrapper = await abrir();

    expect(wrapper.find('#nova-conversa-assunto').exists()).toBe(false);
    await wrapper.find('[data-editor]').setValue('Segue o orçamento');
    expect(principal(wrapper).attributes('disabled')).toBeUndefined();
    await principal(wrapper).trigger('click');
    await flushPromises();

    const [[, pendente]] = respondeu();
    expect(pendente.conversationId).toBe(77);
    expect(pendente.message).toBe('Segue o orçamento');
    expect(pendente).toHaveProperty('ccEmails', '');
  });

  it('não deixa enviar enquanto confere a conversa e avisa se falhar', async () => {
    estado.show = vi.fn(async () => {
      throw new Error('fora do ar');
    });
    const wrapper = await abrir();

    expect(wrapper.find('[data-nova-conversa-erro-conversa]').exists()).toBe(
      true
    );
    expect(wrapper.find('#nova-conversa-texto').exists()).toBe(false);
    expect(principal(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('NOVA_CONVERSA.RODAPE.FALTA.CONVERSA');

    // Escolher começar outra não depende da conversa: libera a mensagem.
    await comecar(wrapper).setValue(true);
    expect(wrapper.find('#nova-conversa-texto').exists()).toBe(true);
  });

  it('trocar de canal zera a escolha: o padrão volta a continuar', async () => {
    estado.canais = [SITE_COM_CONVERSA, { ...EMAIL, id: 8 }];
    const wrapper = await abrir();

    await wrapper
      .findAll('input[name="nova-conversa-canal"]')
      .find(input => input.element.value === '5')
      .setValue(true);
    await flushPromises();
    await comecar(wrapper).setValue(true);
    expect(continuar(wrapper).element.checked).toBe(false);

    await wrapper
      .findAll('input[name="nova-conversa-canal"]')
      .find(input => input.element.value === '8')
      .setValue(true);
    await flushPromises();

    expect(continuar(wrapper).element.checked).toBe(true);
    expect(wrapper.find('[data-nova-conversa-continuar]').text()).toContain(
      `${ONDE}.CONTINUAR:77`
    );
  });
});
