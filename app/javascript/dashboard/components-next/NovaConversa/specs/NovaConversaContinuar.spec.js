import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import conversaActions from 'dashboard/store/modules/conversations/actions';
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
  axios: null,
}));

const traduz = (chave, dados) =>
  dados ? `${chave}:${Object.values(dados).join(',')}` : chave;

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: traduz }),
  // O título da gaveta põe o nome por slot (#2255).
  I18nT: {
    props: ['keypath'],
    template: '<span>{{ keypath }}:<slot name="nome" /></span>',
  },
}));
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
      'inboxes/getConversationWhatsAppTemplates': () => estado.modelos,
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
  visible: true,
  ...dados,
});
const SITE = {
  id: 5,
  name: 'Loja',
  channelType: INBOX_TYPES.WEB,
  sourceId: 's5',
};
// Site nunca chega com conversa: o servidor só oferece o site a quem não tem
// conversa nele (website_contactable_inbox). A caixa de API chega.
const API = {
  id: 5,
  name: 'Integração',
  channelType: INBOX_TYPES.API,
  sourceId: 's5',
};
const API_COM_CONVERSA = { ...API, conversationToContinue: conversa() };
const API_TRAVADA = {
  ...API,
  conversationToContinue: conversa({ status: 'resolved', locked: true }),
};
const API_OCULTA = {
  ...API,
  conversationToContinue: {
    id: null,
    displayId: null,
    status: null,
    lastActivityAt: null,
    locked: true,
    visible: false,
  },
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
    estado.canais = [API_COM_CONVERSA];
    estado.modelos = [];
    estado.podeResponder = true;
    estado.show = vi.fn(async () => ({
      data: { can_reply: estado.podeResponder },
    }));
    // O envio na conversa passa pela ação de verdade (sendMessageWithData →
    // MessageApi.create); só o axios é de mentira.
    estado.axios = vi.fn(async () => ({ data: { id: 900 } }));
    globalThis.axios = estado.axios;
    window.history.pushState({}, '', '/app/accounts/7/contacts/9');
    estado.dispatch = vi.fn(async (acao, dados) => {
      if (acao === 'contactConversations/create') {
        return { id: 42, account_id: 7 };
      }
      if (acao === 'sendMessageWithData') {
        return conversaActions.sendMessageWithData({ commit: vi.fn() }, dados);
      }
      return null;
    });
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
    estado.canais = [API_TRAVADA];
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

  it('o cabeçalho diz "Enviar mensagem" ao continuar e "Nova conversa" ao começar outra', async () => {
    const wrapper = await abrir();
    const rotulo = () => wrapper.find('[data-nova-conversa-heroi]').text();

    expect(rotulo()).toContain('NOVA_CONVERSA.ROTULO_EXISTENTE');
    await comecar(wrapper).setValue(true);
    expect(rotulo()).not.toContain('NOVA_CONVERSA.ROTULO_EXISTENTE');
    expect(rotulo()).toContain('NOVA_CONVERSA.ROTULO');
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
    estado.canais = [API_COM_CONVERSA, { ...EMAIL, id: 8 }];
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

  const postou = () => estado.axios.mock.calls.map(([pedido]) => pedido);

  it('com "Reabrir", envia pela API de mensagem na conversa mostrada', async () => {
    estado.canais = [API_TRAVADA];
    const wrapper = await abrir();

    await wrapper.find('#nova-conversa-texto').setValue('Voltando ao caso');
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(criou()).toHaveLength(0);
    const [pedido] = postou();
    expect(pedido.method).toBe('post');
    expect(pedido.url).toBe('/api/v1/accounts/7/conversations/61/messages');
    expect(pedido.data).toMatchObject({
      content: 'Voltando ao caso',
      private: false,
      cc_emails: '',
      bcc_emails: '',
    });
    expect(wrapper.find('[data-nova-conversa-enviada]').exists()).toBe(true);
  });

  it('se a mensagem não sai, mostra o erro do servidor e não diz "enviada"', async () => {
    estado.axios = vi.fn(async () => {
      throw Object.assign(new Error('422'), {
        response: { data: { error: 'Fora da janela' } },
      });
    });
    globalThis.axios = estado.axios;
    const wrapper = await abrir();

    await wrapper.find('#nova-conversa-texto').setValue('Oi');
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-nova-conversa-enviada]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Fora da janela');
    expect(wrapper.find('#nova-conversa-texto').element.value).toBe('Oi');
    expect(criou()).toHaveLength(0);
  });

  it('a mensagem pronta vai com template_params para a conversa', async () => {
    estado.canais = [WHATSAPP];
    estado.modelos = [MODELO];
    estado.podeResponder = false;
    const wrapper = await abrir();

    await principal(wrapper).trigger('click');
    await flushPromises();

    const [pedido] = postou();
    expect(pedido.url).toBe('/api/v1/accounts/7/conversations/61/messages');
    expect(pedido.data.content).toBe('Oi! Podemos ajudar?');
    expect(pedido.data.template_params.name).toBe('boas_vindas');
  });

  it('conversa que a pessoa não pode ver: avisa sem número, cria pelo servidor e não oferece abrir', async () => {
    estado.canais = [API_OCULTA];
    const wrapper = await abrir();

    expect(wrapper.find('[data-nova-conversa-entra-na-existente]').text()).toBe(
      `${ONDE}.ENTRA_NA_EXISTENTE`
    );
    expect(wrapper.text()).not.toContain(`${ONDE}.ENTRA_NA:`);
    expect(estado.show).not.toHaveBeenCalled();
    await wrapper.find('#nova-conversa-texto').setValue('Oi');
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(criou()).toHaveLength(1);
    expect(postou()).toHaveLength(0);
    expect(wrapper.find('[data-nova-conversa-enviada]').exists()).toBe(true);
    expect(principal(wrapper).exists()).toBe(false);
  });
});
