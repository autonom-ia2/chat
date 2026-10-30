import { createStore } from 'vuex';
import { flushPromises, mount, enableAutoUnmount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import { fetchContactableInboxes } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import { emitter } from 'shared/helpers/mitt';
import ConversaVazia from '../ConversaVazia.vue';
import { BUSCA_DESATUALIZADA } from '../buscaDaLista';
import { criarI18n } from '../../specs/apoio';

// #2211 (rodada 4) — "Escrever" abre a tela da conversa, vazia. As regras de envio são as da
// Nova conversa (composables simulados aqui); o que se testa é a tela: uma caixa já pronta,
// a gaveta "Por onde mandar?" com mais de uma, o telefone novo que só vira contato ao enviar,
// e a conversa criada no lugar da tela vazia.
const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const { useAlert } = await import('dashboard/composables');
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => false }),
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { show: vi.fn(), create: vi.fn() },
}));
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  async importOriginal => ({
    ...(await importOriginal()),
    fetchContactableInboxes: vi.fn(),
    mergeInboxDetails: lista => lista,
  })
);

const CAIXAS_DO_CONTATO = [
  {
    id: 1,
    name: 'WhatsApp Vendas',
    channelType: 'Channel::Whatsapp',
    phoneNumber: '+5511900002202',
  },
  {
    id: 2,
    name: 'E-mail da Corretora',
    channelType: 'Channel::Email',
    email: 'contato@corretora.test',
  },
  { id: 3, name: 'WhatsApp do Celular', channelType: 'Channel::Api' },
];

const contatoDaGaveta = {
  contato: ref(null),
  canais: ref([]),
  carregandoCanais: ref(false),
  erroNosCanais: ref(false),
  escolherContato: vi.fn(),
};
vi.mock(
  'dashboard/components-next/NovaConversa/useNovaConversaContato',
  () => ({ useNovaConversaContato: () => contatoDaGaveta })
);
vi.mock('dashboard/components-next/NovaConversa/useContinuarConversa', () => ({
  useContinuarConversa: () => ({ esperando: ref(false) }),
}));

let usoDaNova = null;
const nova = {
  form: reactive({
    mensagem: '',
    assunto: '',
    cc: '',
    anexos: [],
    modelo: null,
  }),
  tipo: ref('texto'),
  destino: ref(null),
  comModelo: ref(false),
  caixaDoWhatsapp: ref(false),
  soTexto: ref(false),
  assinatura: ref(''),
  comAssinatura: ref(false),
  falta: ref(''),
  enviando: ref(false),
  enviada: ref(null),
  erro: ref(''),
  enviar: vi.fn(),
  enviarPronta: vi.fn(),
};
vi.mock('dashboard/components-next/NovaConversa/useNovaConversa', () => ({
  useNovaConversa: uso => {
    usoDaNova = uso;
    return nova;
  },
}));
vi.mock('../CaixaDaConversaVazia.vue', () => ({
  default: {
    props: ['canal', 'comAssunto'],
    emits: ['enviar', 'enviarPronta'],
    template: `<div :data-com-assunto="String(comAssunto)">
      <button data-caixa-falsa @click="$emit('enviar')">{{ canal.name }}</button>
      <button data-pronta-falsa @click="$emit('enviarPronta', { message: 'Modelo' })" />
    </div>`,
    methods: { montar: () => null },
  },
}));

enableAutoUnmount(afterEach);

// O topo mostra a caixa como o topo da conversa: só quando a conta tem mais de uma.
const DUAS_NA_CONTA = [{ id: 1 }, { id: 2 }];

const montar = (props, caixasDaConta = []) => {
  const store = createStore({
    getters: {
      'inboxes/getInboxes': () => caixasDaConta,
      'inboxes/getInbox': () => () => null,
      getCurrentAccountId: () => 1,
    },
    actions: { 'inboxes/get': vi.fn() },
  });
  return mount(ConversaVazia, {
    // Sem dizer, a busca disse que dá para começar em todas as caixas da conta (caixas_para_comecar).
    props: {
      caixasPermitidas: caixasDaConta.map(caixa => String(caixa.id)),
      ...props,
    },
    global: {
      plugins: [criarI18n(), store],
      stubs: { RouterLink: { template: '<a><slot /></a>' } },
    },
  });
};

const comCaixas = caixas => {
  contatoDaGaveta.escolherContato.mockImplementation(async pessoa => {
    contatoDaGaveta.contato.value = pessoa;
    contatoDaGaveta.canais.value = caixas;
  });
};

describe('ConversaVazia', () => {
  beforeEach(() => {
    push.mockReset();
    nova.enviar.mockReset();
    nova.enviarPronta.mockReset();
    nova.destino.value = null;
    nova.erro.value = '';
    nova.enviando.value = false;
    useAlert.mockReset();
    ContactAPI.create.mockReset();
    fetchContactableInboxes.mockReset();
    nova.enviada.value = null;
    contatoDaGaveta.contato.value = null;
    contatoDaGaveta.canais.value = [];
    ContactAPI.show.mockResolvedValue({
      data: {
        payload: {
          id: 3,
          name: 'Maria da Conceição',
          phone_number: '+5521988887777',
        },
      },
    });
  });

  it('uma caixa só: a tela já vem pronta para escrever, sem gaveta e sem "Trocar"', async () => {
    comCaixas([CAIXAS_DO_CONTATO[0]]);
    const wrapper = montar({ contatoId: '3' }, DUAS_NA_CONTA);
    await flushPromises();
    expect(wrapper.find('[data-nome]').text()).toBe('Maria da Conceição');
    expect(wrapper.find('[data-caixa-escolhida]').text()).toContain(
      'WhatsApp Vendas'
    );
    expect(wrapper.find('[data-por-onde-mandar]').exists()).toBe(false);
    expect(wrapper.find('[data-caixa-falsa]').text()).toBe('WhatsApp Vendas');
    expect(wrapper.find('[data-trocar-caixa]').exists()).toBe(false);
  });

  it('conta com uma caixa só: o topo não repete a caixa, como o topo da conversa', async () => {
    comCaixas([CAIXAS_DO_CONTATO[0]]);
    const wrapper = montar({ contatoId: '3' }, [{ id: 1 }]);
    await flushPromises();
    expect(wrapper.find('[data-caixa-falsa]').exists()).toBe(true);
    expect(wrapper.find('[data-caixa-escolhida]').exists()).toBe(false);
  });

  it('mais de uma: a gaveta abre primeiro; escolher fecha e a caixa fica no cabeçalho com "Trocar"', async () => {
    comCaixas(CAIXAS_DO_CONTATO);
    const wrapper = montar({ contatoId: '3' }, DUAS_NA_CONTA);
    await flushPromises();
    const opcoes = wrapper.findAll('[data-opcao-de-caixa]');
    expect(opcoes).toHaveLength(3);
    expect(opcoes[0].text()).toContain('+55 11 90000-2202');
    expect(opcoes[1].text()).toContain('contato@corretora.test');
    expect(wrapper.find('[data-caixa-falsa]').exists()).toBe(false);

    await opcoes[1].trigger('click');
    expect(wrapper.find('[data-por-onde-mandar]').exists()).toBe(false);
    expect(wrapper.find('[data-caixa-escolhida]').text()).toContain(
      'E-mail da Corretora'
    );
    await wrapper.find('[data-trocar-caixa]').trigger('click');
    expect(wrapper.find('[data-por-onde-mandar]').exists()).toBe(true);
  });

  it('o Instagram não aparece, e a tela diz por quê', async () => {
    comCaixas([
      ...CAIXAS_DO_CONTATO,
      { id: 9, name: 'Insta', channelType: 'Channel::Instagram' },
    ]);
    const wrapper = montar({ contatoId: '3' }, [
      { id: 9, channel_type: 'Channel::Instagram' },
    ]);
    await flushPromises();
    expect(wrapper.findAll('[data-opcao-de-caixa]')).toHaveLength(3);
    expect(wrapper.text()).toContain('só a pessoa pode mandar');
    // Só na gaveta: escolhida a caixa, a conversa não repete o aviso.
    await wrapper.findAll('[data-opcao-de-caixa]')[0].trigger('click');
    expect(wrapper.text()).not.toContain('só a pessoa pode mandar');
  });

  it('sem telefone nem e-mail: diz que não dá para escrever e leva a completar o contato', async () => {
    ContactAPI.show.mockResolvedValue({
      data: { payload: { id: 8, name: 'Pedro Sem Contato' } },
    });
    comCaixas([]);
    const wrapper = montar({ contatoId: '8' });
    await flushPromises();
    expect(wrapper.find('[data-sem-caixa]').text()).toContain(
      'o contato não tem telefone nem e-mail'
    );
    expect(wrapper.find('[data-completar-contato]').exists()).toBe(true);
    expect(wrapper.find('[data-caixa-falsa]').exists()).toBe(false);
  });

  it('telefone novo: o número formatado como nome; o contato só nasce ao enviar', async () => {
    const wrapper = montar({ telefone: '+5511955554444' }, [
      { id: 1, name: 'WhatsApp Vendas', channel_type: 'Channel::Whatsapp' },
      { id: 2, name: 'E-mail', channel_type: 'Channel::Email' },
      { id: 9, name: 'Insta', channel_type: 'Channel::Instagram' },
    ]);
    await flushPromises();
    expect(wrapper.find('[data-nome]').text()).toBe('+55 11 95555-4444');
    expect(ContactAPI.create).not.toHaveBeenCalled();
    // Só uma caixa manda para telefone: já pronta.
    expect(wrapper.find('[data-caixa-falsa]').text()).toBe('WhatsApp Vendas');
    // O rascunho é do número, não do id do contato (que muda ao criar).
    expect(usoDaNova.donoDoRascunho.value).toBe('+5511955554444');

    ContactAPI.create.mockResolvedValue({
      data: { payload: { contact: { id: 77, name: '+55 11 95555-4444' } } },
    });
    fetchContactableInboxes.mockResolvedValue([
      {
        id: 1,
        name: 'WhatsApp Vendas',
        channelType: 'Channel::Whatsapp',
        sourceId: '5511955554444',
      },
    ]);
    await wrapper.find('[data-caixa-falsa]').trigger('click');
    await flushPromises();
    expect(ContactAPI.create).toHaveBeenCalledWith({
      name: '+55 11 95555-4444',
      phone_number: '+5511955554444',
    });
    expect(usoDaNova.contato.value.id).toBe(77);
    expect(usoDaNova.canal.value.sourceId).toBe('5511955554444');
    expect(nova.enviar).toHaveBeenCalledTimes(1);
  });

  it('enviou: a tela vira a conversa criada', async () => {
    comCaixas([CAIXAS_DO_CONTATO[0]]);
    const avisos = vi.fn();
    emitter.on(BUSCA_DESATUALIZADA, avisos);
    montar({ contatoId: '3' });
    await flushPromises();
    nova.enviada.value = { id: 42, contaId: 1 };
    await flushPromises();
    expect(push).toHaveBeenCalledWith({
      path: '/app/accounts/1/conversations/42',
    });
    // A busca aberta na lista refaz o pedido (a pessoa agora tem conversa).
    expect(avisos).toHaveBeenCalledTimes(1);
    emitter.off(BUSCA_DESATUALIZADA, avisos);
  });
  describe('destino novo: erros e repetições', () => {
    const CAIXAS_DA_CONTA = [
      { id: 1, name: 'WhatsApp Vendas', channel_type: 'Channel::Whatsapp' },
    ];
    const DA_CAIXA = [
      {
        id: 1,
        name: 'WhatsApp Vendas',
        channelType: 'Channel::Whatsapp',
        sourceId: '5511955554444',
      },
    ];
    const CRIADO = {
      data: { payload: { contact: { id: 77, name: '+55 11 95555-4444' } } },
    };
    const abrir = async () => {
      const wrapper = montar({ telefone: '+5511955554444' }, CAIXAS_DA_CONTA);
      await flushPromises();
      return wrapper;
    };

    it('modelo do Twilio (enviar pronta): cria o contato antes e só então envia', async () => {
      ContactAPI.create.mockResolvedValue(CRIADO);
      fetchContactableInboxes.mockResolvedValue(DA_CAIXA);
      const wrapper = await abrir();
      await wrapper.find('[data-pronta-falsa]').trigger('click');
      await flushPromises();
      expect(ContactAPI.create).toHaveBeenCalledTimes(1);
      expect(nova.enviarPronta).toHaveBeenCalledWith({ message: 'Modelo' });
      expect(
        ContactAPI.create.mock.invocationCallOrder[0] <
          nova.enviarPronta.mock.invocationCallOrder[0]
      ).toBe(true);
      expect(usoDaNova.contato.value.id).toBe(77);
    });

    it('o servidor recusa o contato (telefone já usado): avisa com o texto dele e não envia', async () => {
      ContactAPI.create.mockRejectedValue({
        response: { data: { message: 'Telefone já está em uso' } },
      });
      const wrapper = await abrir();
      await wrapper.find('[data-caixa-falsa]').trigger('click');
      await flushPromises();
      expect(useAlert).toHaveBeenCalledWith('Telefone já está em uso');
      expect(nova.enviar).not.toHaveBeenCalled();
      expect(fetchContactableInboxes).not.toHaveBeenCalled();
    });

    it('falha sem texto do servidor: avisa com o nosso', async () => {
      ContactAPI.create.mockRejectedValue(new Error('rede'));
      const wrapper = await abrir();
      await wrapper.find('[data-caixa-falsa]').trigger('click');
      await flushPromises();
      expect(useAlert).toHaveBeenCalledWith('Não deu para criar o contato.');
      expect(nova.enviar).not.toHaveBeenCalled();
    });

    it('a caixa não volta: avisa; tentar de novo usa o contato já criado, sem criar outro', async () => {
      ContactAPI.create.mockResolvedValue(CRIADO);
      fetchContactableInboxes.mockResolvedValueOnce([]);
      const wrapper = await abrir();
      await wrapper.find('[data-caixa-falsa]').trigger('click');
      await flushPromises();
      expect(useAlert).toHaveBeenCalledWith(
        'O contato foi criado, mas a caixa não voltou para ele. Tente enviar de novo.'
      );
      expect(nova.enviar).not.toHaveBeenCalled();

      fetchContactableInboxes.mockResolvedValueOnce(DA_CAIXA);
      await wrapper.find('[data-caixa-falsa]').trigger('click');
      await flushPromises();
      expect(ContactAPI.create).toHaveBeenCalledTimes(1);
      expect(fetchContactableInboxes).toHaveBeenLastCalledWith(77);
      expect(nova.enviar).toHaveBeenCalledTimes(1);
    });

    it('o envio falha: o erro aparece', async () => {
      const wrapper = await abrir();
      expect(wrapper.exists()).toBe(true);
      nova.erro.value = 'O WhatsApp recusou a mensagem';
      await flushPromises();
      expect(useAlert).toHaveBeenCalledWith('O WhatsApp recusou a mensagem');
    });

    it('clique duplo: um contato e um envio só', async () => {
      let criar;
      ContactAPI.create.mockReturnValue(
        new Promise(resolve => {
          criar = resolve;
        })
      );
      fetchContactableInboxes.mockResolvedValue(DA_CAIXA);
      const wrapper = await abrir();
      await wrapper.find('[data-caixa-falsa]').trigger('click');
      await wrapper.find('[data-caixa-falsa]').trigger('click');
      criar(CRIADO);
      await flushPromises();
      expect(ContactAPI.create).toHaveBeenCalledTimes(1);
      expect(nova.enviar).toHaveBeenCalledTimes(1);
    });

    it('telefone do link que não é telefone: avisa na abertura, sem caixa', async () => {
      const wrapper = montar({ telefone: '+55119' }, CAIXAS_DA_CONTA);
      await flushPromises();
      expect(wrapper.find('[data-telefone-invalido]').text()).toContain(
        '+55119 não é um telefone válido'
      );
      expect(wrapper.find('[data-caixa-falsa]').exists()).toBe(false);
      expect(wrapper.find('[data-por-onde-mandar]').exists()).toBe(false);
    });
  });

  // inbox_view de função personalizada lista caixas de que a pessoa não é membro: o create da
  // conversa responderia 403 depois de gravar o contato.
  it('telefone novo: a caixa fora das que a busca permitiu não é oferecida; sem nenhuma, avisa', async () => {
    const daConta = [
      { id: 1, name: 'WhatsApp Vendas', channel_type: 'Channel::Whatsapp' },
      { id: 2, name: 'WhatsApp Alheio', channel_type: 'Channel::Whatsapp' },
    ];
    const uma = montar(
      { telefone: '+5511955554444', caixasPermitidas: ['1'] },
      daConta
    );
    await flushPromises();
    expect(uma.find('[data-caixa-falsa]').text()).toBe('WhatsApp Vendas');

    const nenhuma = montar(
      { telefone: '+5511955554444', caixasPermitidas: [] },
      daConta
    );
    await flushPromises();
    expect(nenhuma.find('[data-caixa-falsa]').exists()).toBe(false);
    expect(nenhuma.find('[data-sem-caixa]').exists()).toBe(true);
    expect(ContactAPI.create).not.toHaveBeenCalled();
  });

  describe('e-mail novo', () => {
    it('só caixas de e-mail; o contato nasce com o e-mail ao enviar', async () => {
      const wrapper = montar({ email: 'nova@exemplo.test' }, [
        { id: 1, name: 'WhatsApp Vendas', channel_type: 'Channel::Whatsapp' },
        { id: 2, name: 'E-mail', channel_type: 'Channel::Email' },
      ]);
      await flushPromises();
      expect(wrapper.find('[data-nome]').text()).toBe('nova@exemplo.test');
      expect(wrapper.find('[data-caixa-falsa]').text()).toBe('E-mail');
      // Conversa nova: o Assunto aparece.
      expect(
        wrapper.find('[data-com-assunto]').attributes('data-com-assunto')
      ).toBe('true');
      expect(usoDaNova.donoDoRascunho.value).toBe('nova@exemplo.test');

      ContactAPI.create.mockResolvedValue({
        data: { payload: { contact: { id: 80, email: 'nova@exemplo.test' } } },
      });
      fetchContactableInboxes.mockResolvedValue([
        { id: 2, name: 'E-mail', channelType: 'Channel::Email', sourceId: 'x' },
      ]);
      await wrapper.find('[data-caixa-falsa]').trigger('click');
      await flushPromises();
      // O nome é o da Nova conversa: a parte antes do @, com a primeira letra maiúscula.
      expect(ContactAPI.create).toHaveBeenCalledWith({
        name: 'Nova',
        email: 'nova@exemplo.test',
      });
      expect(nova.enviar).toHaveBeenCalledTimes(1);
    });
  });

  it('continuando uma conversa que já existe, sem Assunto (é o da conversa)', async () => {
    comCaixas([CAIXAS_DO_CONTATO[1]]);
    nova.destino.value = { displayId: 5 };
    const wrapper = montar({ contatoId: '3' });
    await flushPromises();
    expect(
      wrapper.find('[data-com-assunto]').attributes('data-com-assunto')
    ).toBe('false');
  });
});
