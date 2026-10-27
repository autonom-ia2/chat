import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import NovaConversaGaveta from '../NovaConversaGaveta.vue';

// #1459 — a jornada da gaveta de ponta a ponta, com o servidor de mentira:
// abre com o contato, escolhe por onde, escreve (ou escolhe a mensagem
// pronta) e envia pela mesma chamada da tela antiga.
const estado = vi.hoisted(() => ({
  canais: [],
  modelos: [],
  dispatch: null,
  push: null,
  rota: null,
  nome: 'Ana Souza',
  permissoes: [],
  jornadaDeModelos: false,
  achados: [],
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, dados) => (dados?.nome ? `${chave}:${dados.nome}` : chave),
  }),
  // O título põe o nome por slot (#2255): a chave e o nome, como o t() acima.
  I18nT: {
    props: ['keypath'],
    template: '<span>{{ keypath }}:<slot name="nome" /></span>',
  },
}));
vi.mock('vue-router', () => ({
  useRoute: () => estado.rota,
  useRouter: () => ({ push: estado.push, hasRoute: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: estado.dispatch }),
  useMapGetter: nome => {
    const getters = {
      'inboxes/getInboxes': [],
      'contacts/getContactById': id => ({
        id: Number(id),
        name: Number(id) === 10 ? 'Bia Lima' : estado.nome,
      }),
      'inboxes/getConversationWhatsAppTemplates': () => estado.modelos,
      'inboxes/getInbox': () => ({}),
      'accounts/isRTL': false,
      getCurrentUser: { id: 3 },
      getCurrentAccountId: 7,
      'accounts/isFeatureEnabledonAccount': (_conta, flag) =>
        flag === 'whatsapp_templates_journey' && estado.jornadaDeModelos,
      'globalConfig/get': { directUploadsEnabled: false },
      getMessageSignature: '',
    };
    return ref(getters[nome]);
  },
}));
vi.mock('dashboard/helper/permissionsHelper.js', () => ({
  getUserPermissions: () => estado.permissoes,
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
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  async original => ({
    ...(await original()),
    fetchContactableInboxes: vi.fn(async () => estado.canais),
    createContactSearcher: () => vi.fn(async () => estado.achados),
  })
);
// A busca sai na hora, sem a espera de digitação.
vi.mock('@chatwoot/utils', async original => ({
  ...(await original()),
  debounce: funcao => funcao,
}));

const SITE = {
  id: 5,
  name: 'Loja',
  channelType: INBOX_TYPES.WEB,
  sourceId: 's5',
};
const WHATSAPP = {
  id: 1,
  name: 'Vendas',
  channelType: INBOX_TYPES.WHATSAPP,
  phoneNumber: '+5511999990000',
  sourceId: 's1',
};
const WHATSAPP_LIVRE = { ...WHATSAPP, whatsappApiStart: true };
const EMAIL = {
  id: 4,
  name: 'Contato',
  channelType: INBOX_TYPES.EMAIL,
  email: 'oi@loja.com',
  sourceId: 's4',
};
const MODELO = {
  id: 10,
  name: 'boas_vindas',
  language: 'pt_BR',
  category: 'UTILITY',
  components: [{ type: 'BODY', text: 'Oi! Podemos ajudar?' }],
};
const MODELO_COM_CAMPOS = {
  id: 11,
  name: 'lembrete_de_horario',
  language: 'pt_BR',
  category: 'UTILITY',
  components: [
    {
      type: 'BODY',
      text: 'Oi, {{1}}. Seu horário é {{2}}.',
      example: { body_text: [['Mariana', 'sexta, 9h']] },
    },
  ],
};

const abrir = async (props = { contactId: '9' }) => {
  const wrapper = mount(NovaConversaGaveta, {
    props,
    slots: { trigger: '<button data-abrir>Enviar mensagem</button>' },
    attachTo: document.body,
    global: {
      mocks: {
        $t: (chave, dados) => (dados?.nome ? `${chave}:${dados.nome}` : chave),
      },
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        transition: true,
        FileUpload: { template: '<span><slot /></span>' },
        // O editor de e-mail entrega texto com marcação; aqui, um campo simples.
        MessageEditor: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template: `<textarea data-editor :value="modelValue"
            @input="$emit('update:modelValue', $event.target.value)" />`,
        },
        EmailOptions: {
          props: ['ccEmails'],
          emits: ['update:ccEmails'],
          template: `<input data-copia :value="ccEmails"
            @input="$emit('update:ccEmails', $event.target.value)" />`,
        },
        Avatar: true,
      },
    },
  });
  // No navegador, clicar no botão já põe o foco nele.
  wrapper.find('[data-abrir]').element.focus();
  await wrapper.find('[data-abrir]').trigger('click');
  await flushPromises();
  return wrapper;
};

const principal = wrapper => wrapper.find('[data-nova-conversa-principal]');
const titulo = wrapper => wrapper.find('[data-view-title]').text();
const temPrevia = wrapper => wrapper.find('[data-funil-previa]').exists();
const enviou = () =>
  estado.dispatch.mock.calls.find(
    ([acao]) => acao === 'contactConversations/create'
  );
const F = 'NOVA_CONVERSA.RODAPE.FALTA';

describe('NovaConversaGaveta', () => {
  beforeEach(() => {
    estado.canais = [SITE];
    estado.modelos = [];
    estado.nome = 'Ana Souza';
    estado.permissoes = ['agent'];
    estado.jornadaDeModelos = false;
    estado.achados = [];
    estado.rota = { name: 'home', params: { accountId: 7 } };
    estado.dispatch = vi.fn(async acao =>
      acao === 'contactConversations/create' ? { id: 42, account_id: 7 } : null
    );
    estado.push = vi.fn();
    useKeyboardEvents.mockClear();
  });

  it('abre como diálogo com o nome do contato e sem o bloco "Para quem"', async () => {
    const wrapper = await abrir();

    const gaveta = wrapper.find('[data-nova-conversa-gaveta]');
    expect(gaveta.attributes('role')).toBe('dialog');
    expect(gaveta.attributes('aria-modal')).toBe('true');
    expect(titulo(wrapper)).toBe('NOVA_CONVERSA.TITULO:Ana Souza');
    expect(wrapper.text()).toContain('NOVA_CONVERSA.TEXTO');
    expect(wrapper.find('#nova-conversa-busca').exists()).toBe(false);
    expect(temPrevia(wrapper)).toBe(true);
    expect(estado.dispatch).toHaveBeenCalledWith('inboxes/get');
  });

  it('sem contato, só pede a busca: sem prévia e sem botão de enviar', async () => {
    const wrapper = await abrir({});

    expect(titulo(wrapper)).toBe('NOVA_CONVERSA.TITULO_SEM_CONTATO');
    expect(wrapper.text()).toContain('NOVA_CONVERSA.TEXTO_BUSCA');
    expect(document.activeElement).toBe(
      wrapper.find('#nova-conversa-busca').element
    );
    expect(temPrevia(wrapper)).toBe(false);
    expect(principal(wrapper).exists()).toBe(false);
    expect(wrapper.find('[data-nova-conversa-fechar-rodape]').exists()).toBe(
      true
    );
  });

  describe('contato sem telefone nem e-mail', () => {
    beforeEach(() => {
      estado.canais = [];
    });

    it('vira um estado vazio com o primeiro nome e uma ação só', async () => {
      const wrapper = await abrir();

      const vazio = wrapper.find('[data-nova-conversa-sem-canal]');
      expect(vazio.text()).toContain('NOVA_CONVERSA.POR_ONDE.VAZIO:Ana');
      expect(vazio.text()).not.toContain('Souza');
      expect(wrapper.text()).not.toContain('NOVA_CONVERSA.TEXTO');
      expect(temPrevia(wrapper)).toBe(false);
      expect(wrapper.find('[data-nova-conversa-mensagem]').exists()).toBe(
        false
      );
      expect(wrapper.findAll('[data-nova-conversa-principal]')).toHaveLength(1);
      expect(vazio.find('[data-nova-conversa-principal]').exists()).toBe(true);
    });

    it('leva ao cadastro do contato quando abre de outro lugar', async () => {
      const wrapper = await abrir();

      await principal(wrapper).trigger('click');

      expect(estado.push).toHaveBeenCalledWith({
        name: 'contacts_edit',
        params: { accountId: 7, contactId: 9 },
      });
      expect(wrapper.find('[data-nova-conversa-gaveta]').exists()).toBe(false);
    });

    it('só fecha quando já está na página do contato', async () => {
      estado.rota = {
        name: 'contacts_edit',
        params: { accountId: 7, contactId: '9' },
      };
      const wrapper = await abrir();

      await principal(wrapper).trigger('click');

      expect(estado.push).not.toHaveBeenCalled();
      expect(wrapper.find('[data-nova-conversa-gaveta]').exists()).toBe(false);
    });
  });

  it('envia o texto escrito e mostra o que foi enviado e por onde', async () => {
    const wrapper = await abrir();
    expect(wrapper.text()).toContain(`${F}.MENSAGEM`);

    await wrapper.find('#nova-conversa-texto').setValue('Oi, Ana!');
    expect(wrapper.find('[data-previa-balao]').text()).toContain('Oi, Ana!');
    expect(principal(wrapper).attributes('disabled')).toBeUndefined();
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(enviou()[1]).toEqual({
      params: {
        inboxId: 5,
        sourceId: 's5',
        contactId: 9,
        message: { content: 'Oi, Ana!' },
        assigneeId: 3,
      },
      isFromWhatsApp: false,
    });
    expect(titulo(wrapper)).toBe('NOVA_CONVERSA.ENVIADA.TITULO:Ana Souza');
    expect(wrapper.text()).not.toContain('NOVA_CONVERSA.TEXTO');
    const enviada = wrapper.find('[data-nova-conversa-enviada]');
    expect(enviada.find('[data-previa-balao]').text()).toContain('Oi, Ana!');
    expect(enviada.find('[data-nova-conversa-enviada-canal]').text()).toBe(
      'NOVA_CONVERSA.ENVIADA.PELO.SITE'
    );
    expect(wrapper.find('[data-nova-conversa-fechar-rodape]').exists()).toBe(
      true
    );
    await principal(wrapper).trigger('click');
    expect(estado.push).toHaveBeenCalledWith(
      '/app/accounts/7/conversations/42'
    );
  });

  it('já marca a única mensagem pronta e envia o modelo', async () => {
    estado.canais = [WHATSAPP];
    estado.modelos = [MODELO];
    const wrapper = await abrir();

    expect(wrapper.find('#nova-conversa-texto').exists()).toBe(false);
    expect(wrapper.find('input[name="nova-conversa-pronta"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-previa-balao]').text()).toContain(
      'Oi! Podemos ajudar?'
    );
    expect(principal(wrapper).attributes('disabled')).toBeUndefined();
    await principal(wrapper).trigger('click');
    await flushPromises();

    const [, envio] = enviou();
    expect(envio.isFromWhatsApp).toBe(true);
    expect(envio.params.inboxId).toBe(1);
    expect(envio.params.message.content).toBe('Oi! Podemos ajudar?');
    expect(envio.params.message.template_params.name).toBe('boas_vindas');
    expect(
      wrapper.find('[data-nova-conversa-enviada] [data-previa-balao]').text()
    ).toContain('Oi! Podemos ajudar?');
    expect(wrapper.find('[data-nova-conversa-enviada-canal]').text()).toBe(
      'NOVA_CONVERSA.ENVIADA.PELO.WHATSAPP'
    );
  });

  it('lista as mensagens prontas com os campos em pastilha, sem marcar', async () => {
    estado.canais = [WHATSAPP];
    estado.modelos = [MODELO, MODELO_COM_CAMPOS];
    const wrapper = await abrir();

    const opcoes = wrapper.findAll('input[name="nova-conversa-pronta"]');
    expect(opcoes).toHaveLength(2);
    expect(opcoes.some(opcao => opcao.element.checked)).toBe(false);
    expect(document.activeElement).toBe(opcoes[0].element);
    expect(wrapper.findAll('[data-campo-variavel]')).toHaveLength(2);
    expect(wrapper.text()).not.toContain('{{1}}');
    expect(wrapper.text()).toContain(`${F}.MODELO`);
  });

  it('completa a mensagem pronta: todo campo vazio, com o exemplo do modelo', async () => {
    estado.canais = [WHATSAPP];
    estado.modelos = [MODELO_COM_CAMPOS];
    const wrapper = await abrir();

    const campos = wrapper.findAll('[data-nova-conversa-campos] input');
    expect(campos).toHaveLength(2);
    // Nada vem preenchido: {{1}} pode não ser o nome de quem recebe.
    expect(campos[0].element.value).toBe('');
    expect(campos[1].element.value).toBe('');
    expect(campos[1].attributes('placeholder')).toBe(
      'NOVA_CONVERSA.MENSAGEM.CAMPO_EXEMPLO'
    );
    // O rótulo é o trecho da mensagem em volta do campo, com a pastilha.
    const rotulos = wrapper.findAll('[data-nova-conversa-campos] label');
    expect(rotulos[0].text()).toContain('Oi,');
    expect(rotulos[0].text()).toContain('. Seu horário é');
    expect(rotulos[0].findAll('[data-campo-alvo]')).toHaveLength(1);
    expect(campos[0].attributes('aria-label')).toBe(
      'Oi, NOVA_CONVERSA.MENSAGEM.CAMPO_FALADO. Seu horário é'
    );
    expect(document.activeElement).toBe(campos[0].element);
    expect(wrapper.text()).toContain(`${F}.CAMPOS`);
    expect(principal(wrapper).attributes('disabled')).toBeDefined();

    await campos[1].setValue('sexta, 9h');
    expect(principal(wrapper).attributes('disabled')).toBeDefined();
    await campos[0].setValue('Ana');
    expect(wrapper.find('[data-previa-balao]').text()).toContain(
      'Oi, Ana. Seu horário é sexta, 9h.'
    );
    await principal(wrapper).trigger('click');
    await flushPromises();

    const { message } = enviou()[1].params;
    expect(message.content).toBe('Oi, {{1}}. Seu horário é {{2}}.');
    expect(message.template_params).toEqual({
      name: 'lembrete_de_horario',
      category: 'UTILITY',
      language: 'pt_BR',
      namespace: undefined,
      content_mode: 'raw_template',
      processed_params: { body: { 1: 'Ana', 2: 'sexta, 9h' } },
    });
  });

  it('deixa escrever ou usar a pronta quando o texto livre vale', async () => {
    estado.canais = [{ ...WHATSAPP, whatsappApiStart: true }];
    estado.modelos = [MODELO];
    const wrapper = await abrir();

    expect(wrapper.find('#nova-conversa-texto').exists()).toBe(true);
    const modos = wrapper.findAll('input[name="nova-conversa-modo"]');
    expect(modos).toHaveLength(2);
    expect(modos[0].element.checked).toBe(true);

    await modos[1].setValue();
    expect(wrapper.find('#nova-conversa-texto').exists()).toBe(false);
    // Com texto livre, a única pronta não vem marcada: a pessoa escolhe.
    expect(wrapper.find('input[name="nova-conversa-pronta"]').exists()).toBe(
      true
    );
  });

  describe('sem mensagem pronta aprovada', () => {
    const P = 'NOVA_CONVERSA.MENSAGEM';
    const vazio = wrapper => wrapper.find('[data-nova-conversa-sem-pronta]');

    beforeEach(() => {
      estado.canais = [WHATSAPP];
    });

    it('quem não pode criar só lê a frase e a quem pedir', async () => {
      const wrapper = await abrir();

      expect(vazio(wrapper).text()).toContain(`${P}.SEM_PRONTA`);
      expect(vazio(wrapper).text()).toContain(`${P}.SEM_PRONTA_PECA`);
      expect(vazio(wrapper).find('button').exists()).toBe(false);
      expect(principal(wrapper).attributes('disabled')).toBeDefined();
    });

    it('quem tem a função de modelos vai direto para criar, na caixa escolhida', async () => {
      estado.permissoes = ['whatsapp_templates_manage'];
      estado.jornadaDeModelos = true;
      const wrapper = await abrir();

      expect(vazio(wrapper).text()).not.toContain(`${P}.SEM_PRONTA_PECA`);
      await vazio(wrapper).find('button').trigger('click');

      expect(estado.push).toHaveBeenCalledWith({
        name: 'modelos_whatsapp_novo',
        params: { accountId: 7 },
        query: { caixa: 1 },
      });
      expect(wrapper.find('[data-nova-conversa-gaveta]').exists()).toBe(false);
    });

    it('sem a jornada de modelos, o administrador vai para a lista', async () => {
      estado.permissoes = ['administrator'];
      const wrapper = await abrir();

      await vazio(wrapper).find('button').trigger('click');

      expect(estado.push).toHaveBeenCalledWith({
        name: 'modelos_whatsapp_lista',
        params: { accountId: 7 },
      });
    });
  });

  it('põe os canais lado a lado, com o primeiro marcado e o telefone legível', async () => {
    estado.canais = [SITE, WHATSAPP];
    const wrapper = await abrir();

    const opcoes = wrapper.findAll('input[name="nova-conversa-canal"]');
    expect(opcoes).toHaveLength(2);
    // ordenarCanais põe o WhatsApp antes do site.
    expect(opcoes[0].element.value).toBe('1');
    expect(opcoes[0].element.checked).toBe(true);
    expect(wrapper.find('fieldset').classes()).toContain('sm:grid-cols-2');
    expect(wrapper.text()).toContain('+55 11 99999-0000');

    await opcoes[1].setValue();
    expect(wrapper.find('#nova-conversa-texto').exists()).toBe(true);
  });

  it('mantém o que foi escrito e avisa quando o envio falha', async () => {
    estado.dispatch = vi.fn(async acao => {
      if (acao === 'contactConversations/create') throw new Error('falhou');
      return null;
    });
    const wrapper = await abrir();

    await wrapper.find('#nova-conversa-texto').setValue('Oi, Ana!');
    await principal(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-nova-conversa-erro]').text()).toContain(
      'NOVA_CONVERSA.ERRO.PADRAO'
    );
    expect(wrapper.find('#nova-conversa-texto').element.value).toBe('Oi, Ana!');
    expect(wrapper.find('[data-nova-conversa-enviada]').exists()).toBe(false);
  });

  it('envia com Ctrl+Enter e não com Enter sozinho', async () => {
    const wrapper = await abrir();
    const campo = wrapper.find('#nova-conversa-texto');
    await campo.setValue('Oi');

    await campo.trigger('keydown', { key: 'Enter' });
    expect(enviou()).toBeUndefined();
    await campo.trigger('keydown', { key: 'Enter', ctrlKey: true });
    expect(enviou()).toBeDefined();
  });

  describe('o que foi escrito para um contato não segue para outro', () => {
    const escolher = async (wrapper, pessoa) => {
      estado.achados = [pessoa];
      await wrapper.find('#nova-conversa-busca').setValue(pessoa.name);
      await flushPromises();
      await wrapper.find('[data-nova-conversa-achado]').trigger('click');
      await flushPromises();
    };
    const ANA = { id: 9, name: 'Ana Souza', phoneNumber: '+5511988887777' };
    const BIA = { id: 10, name: 'Bia Lima', email: 'bia@exemplo.com' };

    it('zera a mensagem ao trocar de contato pelo "Alterar"', async () => {
      const wrapper = await abrir({});
      await escolher(wrapper, ANA);
      await wrapper.find('#nova-conversa-texto').setValue('Segredo da Ana');

      await wrapper.find('article button').trigger('click');
      expect(wrapper.find('#nova-conversa-busca').exists()).toBe(true);
      await escolher(wrapper, BIA);

      expect(titulo(wrapper)).toBe('NOVA_CONVERSA.TITULO:Bia Lima');
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe('');
      expect(wrapper.text()).not.toContain('Segredo da Ana');
    });

    it('zera também se a pessoa volta para o mesmo contato depois de limpar', async () => {
      const wrapper = await abrir({});
      await escolher(wrapper, ANA);
      await wrapper.find('#nova-conversa-texto').setValue('Rascunho');

      await wrapper.find('article button').trigger('click');
      await escolher(wrapper, ANA);

      expect(wrapper.find('#nova-conversa-texto').element.value).toBe('');
    });

    it('acompanha a página quando o contato muda com a gaveta aberta', async () => {
      const wrapper = await abrir();
      await wrapper.find('#nova-conversa-texto').setValue('Segredo da Ana');

      await wrapper.setProps({ contactId: '10' });
      await flushPromises();

      expect(titulo(wrapper)).toBe('NOVA_CONVERSA.TITULO:Bia Lima');
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe('');
    });

    it('zera ao reabrir com outro contato, e mantém ao reabrir com o mesmo', async () => {
      const wrapper = await abrir();
      await wrapper.find('#nova-conversa-texto').setValue('Rascunho da Ana');

      await wrapper.find('[data-nova-conversa-fechar]').trigger('click');
      await wrapper.find('[data-abrir]').trigger('click');
      await flushPromises();
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe(
        'Rascunho da Ana'
      );

      await wrapper.find('[data-nova-conversa-fechar]').trigger('click');
      await wrapper.setProps({ contactId: '10' });
      await wrapper.find('[data-abrir]').trigger('click');
      await flushPromises();
      expect(wrapper.find('#nova-conversa-texto').element.value).toBe('');
    });

    it('mantém o texto ao trocar só o canal do mesmo contato', async () => {
      estado.canais = [SITE, WHATSAPP_LIVRE];
      const wrapper = await abrir();
      await wrapper.find('#nova-conversa-texto').setValue('Oi, Ana!');

      await wrapper.findAll('input[name="nova-conversa-canal"]')[1].setValue();

      expect(wrapper.find('#nova-conversa-texto').element.value).toBe(
        'Oi, Ana!'
      );
    });
  });

  describe('e-mail', () => {
    beforeEach(() => {
      estado.canais = [EMAIL];
    });

    it('mostra a prévia sem a marcação de formatação do editor', async () => {
      const wrapper = await abrir();

      await wrapper.find('#nova-conversa-assunto').setValue('Proposta');
      await wrapper.find('[data-editor]').setValue('**Oi**, _Ana_!');

      const corpo = wrapper.find('[data-nova-conversa-email-corpo]');
      expect(corpo.text()).toBe('Oi, Ana!');
      expect(wrapper.find('[data-previa-balao]').exists()).toBe(false);
    });

    it('confirma o envio com o cartão de e-mail, e não com balão', async () => {
      const wrapper = await abrir();
      await wrapper.find('#nova-conversa-assunto').setValue('Proposta');
      await wrapper.find('[data-editor]').setValue('**Oi**, Ana!');

      await principal(wrapper).trigger('click');
      await flushPromises();

      const { params } = enviou()[1];
      expect(params.mailSubject).toBe('Proposta');
      expect(params.message.content).toBe('**Oi**, Ana!');
      const enviada = wrapper.find('[data-nova-conversa-enviada]');
      expect(enviada.find('[data-previa-balao]').exists()).toBe(false);
      expect(enviada.find('[data-nova-conversa-email-assunto]').text()).toBe(
        'Proposta'
      );
      expect(enviada.find('[data-nova-conversa-email-corpo]').text()).toBe(
        'Oi, Ana!'
      );
      expect(enviada.text()).toContain('oi@loja.com');
      expect(enviada.find('[data-nova-conversa-enviada-canal]').text()).toBe(
        'NOVA_CONVERSA.ENVIADA.PELO.EMAIL'
      );
    });

    it('abre "Mais opções" sozinho quando já há cópia preenchida', async () => {
      estado.canais = [EMAIL, SITE];
      const wrapper = await abrir();
      const mais = () => wrapper.find('[data-nova-conversa-mais]');
      expect(mais().attributes('aria-expanded')).toBe('false');
      await mais().trigger('click');
      await wrapper.find('[data-copia]').setValue('chefe@loja.com');

      // Sai do e-mail e volta: a cópia continua valendo, então fica à vista.
      const canais = wrapper.findAll('input[name="nova-conversa-canal"]');
      await canais[1].setValue();
      await canais[0].setValue();

      expect(mais().attributes('aria-expanded')).toBe('true');
      expect(wrapper.find('[data-copia]').element.value).toBe('chefe@loja.com');
    });
  });

  it('devolve o sinal de "conversa nova aberta" se some da tela ainda aberta', async () => {
    const sinal = vi.spyOn(emitter, 'emit');
    const wrapper = await abrir();
    expect(sinal).toHaveBeenLastCalledWith(
      BUS_EVENTS.NEW_CONVERSATION_MODAL,
      true
    );

    wrapper.unmount();

    expect(sinal).toHaveBeenLastCalledWith(
      BUS_EVENTS.NEW_CONVERSATION_MODAL,
      false
    );
    sinal.mockRestore();
  });

  describe('foco', () => {
    it('vai para o campo da mensagem ao abrir com contato', async () => {
      const wrapper = await abrir();

      expect(document.activeElement).toBe(
        wrapper.find('#nova-conversa-texto').element
      );
    });

    it('dá a volta dentro da gaveta com Tab e Shift+Tab', async () => {
      const wrapper = await abrir();
      const fechar = wrapper.find('[data-nova-conversa-fechar]');
      const cancelar = wrapper.findAll('footer button')[0];

      // O botão de enviar está desligado: o último que recebe foco é Cancelar.
      cancelar.element.focus();
      await cancelar.trigger('keydown', { key: 'Tab' });
      expect(document.activeElement).toBe(fechar.element);

      await fechar.trigger('keydown', { key: 'Tab', shiftKey: true });
      expect(document.activeElement).toBe(cancelar.element);
    });

    it('fecha pelo X, avisa quem abriu e volta ao botão que abriu', async () => {
      const wrapper = await abrir();

      await wrapper.find('[data-nova-conversa-fechar]').trigger('click');

      expect(wrapper.find('[data-nova-conversa-gaveta]').exists()).toBe(false);
      expect(wrapper.emitted('close')).toHaveLength(1);
      expect(document.activeElement).toBe(wrapper.find('[data-abrir]').element);
    });

    it('fecha com Esc e volta ao botão que abriu', async () => {
      const wrapper = await abrir();
      const { Escape } = useKeyboardEvents.mock.calls.at(-1)[0];

      Escape.action({ target: wrapper.find('#nova-conversa-texto').element });
      await flushPromises();

      expect(Escape.allowOnFocusedInput).toBe(true);
      expect(wrapper.find('[data-nova-conversa-gaveta]').exists()).toBe(false);
      expect(document.activeElement).toBe(wrapper.find('[data-abrir]').element);
    });
  });
});
