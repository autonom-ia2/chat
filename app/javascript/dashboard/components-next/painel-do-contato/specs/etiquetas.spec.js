import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import BlocoEtiquetas from '../etiquetas/BlocoEtiquetas.vue';
import EtiquetasDaConversaDialog from '../etiquetas/EtiquetasDaConversaDialog.vue';
import { criarI18n, criarStore } from './apoio';

// #2202 (PR 3) — etiquetas da conversa no painel novo: o bloco aparece só quando
// a conversa tem etiqueta, cada uma com cor e nome; quem opera toca e abre a
// escolha; quem só lê vê sem botão. A escolha usa as actions de sempre.
vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

enableAutoUnmount(afterEach);

const CONVERSA = { id: 42, inbox_id: 1, meta: {} };
const ETIQUETAS_DA_CONTA = [
  { id: 1, title: 'vip', color: '#ff0000' },
  { id: 2, title: 'retorno', color: '#00aa00' },
  { id: 3, title: 'boleto', color: '#0000ff' },
];

const abrir = vi.fn();
const EscolhaStub = {
  template: '<div data-escolha />',
  methods: { abrir },
};

const montarBloco = ({ etiquetas = [], podeOperar = true } = {}) => {
  const apoio = criarStore({
    conversaSelecionada: CONVERSA,
    etiquetasDaConta: ETIQUETAS_DA_CONTA,
    etiquetasDaConversa: { 42: etiquetas },
  });
  const wrapper = mount(BlocoEtiquetas, {
    props: { podeOperar },
    global: {
      plugins: [apoio.store, criarI18n()],
      stubs: { EtiquetasDaConversaDialog: EscolhaStub },
    },
  });
  return { wrapper, ...apoio };
};

beforeEach(() => vi.clearAllMocks());

describe('BlocoEtiquetas', () => {
  it('conversa sem etiqueta: o bloco não aparece', () => {
    const { wrapper } = montarBloco();
    expect(wrapper.find('[data-test-id="bloco-etiquetas"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).not.toContain('Etiquetas');
  });

  it('com etiqueta: título, nome e cor de cada uma', () => {
    const { wrapper } = montarBloco({ etiquetas: ['vip', 'retorno'] });
    const bloco = wrapper.get('[data-test-id="bloco-etiquetas"]');
    expect(bloco.get('h3').text()).toBe('Etiquetas');
    const itens = bloco.findAll('li');
    expect(itens.map(item => item.text())).toEqual(['vip', 'retorno']);
    expect(itens[0].get('span').attributes('style')).toContain(
      'background-color: rgb(255, 0, 0)'
    );
    expect(bloco.text()).not.toContain('boleto');
  });

  it('quem opera toca nas etiquetas e abre a escolha', async () => {
    const { wrapper } = montarBloco({ etiquetas: ['vip'] });
    const alvo = wrapper.get('[data-test-id="etiquetas-da-conversa"]');
    expect(alvo.element.tagName).toBe('BUTTON');
    expect(alvo.attributes('aria-label')).toBe(
      'Mudar as etiquetas desta conversa'
    );
    expect(alvo.classes()).toContain('min-h-11');
    await alvo.trigger('click');
    expect(abrir).toHaveBeenCalledTimes(1);
  });

  it('quem só lê vê as etiquetas sem botão e sem a escolha', async () => {
    const { wrapper } = montarBloco({ etiquetas: ['vip'], podeOperar: false });
    const alvo = wrapper.get('[data-test-id="etiquetas-da-conversa"]');
    expect(alvo.element.tagName).toBe('DIV');
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.find('[data-escolha]').exists()).toBe(false);
    await alvo.trigger('click');
    expect(abrir).not.toHaveBeenCalled();
  });

  it('tirar a última etiqueta some com o bloco, mas não com a escolha', async () => {
    const { wrapper, dados } = montarBloco({ etiquetas: ['vip'] });
    dados.etiquetasDaConversa = { 42: [] };
    await flushPromises();
    expect(wrapper.find('[data-test-id="bloco-etiquetas"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-escolha]').exists()).toBe(true);
  });
});

describe('EtiquetasDaConversaDialog', () => {
  const DialogStub = {
    props: ['title', 'description'],
    methods: { open() {}, close() {} },
    template:
      '<div><h3>{{ title }}</h3><p>{{ description }}</p><slot /><slot name="footer" /></div>',
  };
  const ListaStub = {
    name: 'LabelDropdown',
    props: ['accountLabels', 'selectedLabels', 'allowCreation'],
    emits: ['add', 'remove'],
    template: '<div data-lista />',
  };

  const montarEscolha = ({
    etiquetas = ['vip'],
    papel = 'agent',
    permissoes = [],
    erro = false,
  } = {}) => {
    const apoio = criarStore({
      conversaSelecionada: CONVERSA,
      etiquetasDaConta: ETIQUETAS_DA_CONTA,
      etiquetasDaConversa: { 42: etiquetas },
      papel,
      permissoes,
      respostas: {
        'conversationLabels/update': (_payload, r) => {
          r.uiEtiquetas = { isError: erro };
        },
      },
    });
    const wrapper = mount(EtiquetasDaConversaDialog, {
      global: {
        plugins: [apoio.store, criarI18n()],
        stubs: { Dialog: DialogStub, LabelDropdown: ListaStub, Button: true },
      },
    });
    return { wrapper, lista: wrapper.findComponent(ListaStub), ...apoio };
  };

  it('mostra a lista de sempre com as etiquetas da conversa marcadas', () => {
    const { wrapper, lista } = montarEscolha();
    expect(wrapper.text()).toContain('Etiquetas desta conversa');
    expect(wrapper.text()).toContain('Toque numa etiqueta para pôr ou tirar.');
    expect(lista.props('selectedLabels')).toEqual(['vip']);
  });

  it('as etiquetas que a conversa já tem vêm primeiro na lista', () => {
    const { lista } = montarEscolha({ etiquetas: ['boleto', 'retorno'] });
    expect(lista.props('accountLabels').map(label => label.title)).toEqual([
      'retorno',
      'boleto',
      'vip',
    ]);
  });

  it('pôr e tirar etiqueta usam a action de sempre, com a conversa aberta', async () => {
    const { lista, acoes } = montarEscolha({ etiquetas: ['vip', 'retorno'] });
    lista.vm.$emit('add', { title: 'boleto' });
    await flushPromises();
    lista.vm.$emit('remove', 'vip');
    await flushPromises();
    expect(acoes).toEqual([
      [
        'conversationLabels/update',
        { conversationId: 42, labels: ['vip', 'retorno', 'boleto'] },
      ],
      [
        'conversationLabels/update',
        { conversationId: 42, labels: ['retorno'] },
      ],
    ]);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('erro ao salvar: avisa em frase simples', async () => {
    const { lista } = montarEscolha({ erro: true });
    lista.vm.$emit('add', { title: 'boleto' });
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar a etiqueta. Tente de novo.'
    );
  });

  it('criar etiqueta só para quem administra etiquetas', () => {
    expect(montarEscolha().lista.props('allowCreation')).toBe(false);
    expect(
      montarEscolha({
        papel: 'administrator',
        permissoes: ['administrator'],
      }).lista.props('allowCreation')
    ).toBe(true);
    expect(
      montarEscolha({
        permissoes: ['conversation_manage', 'label_manage'],
      }).lista.props('allowCreation')
    ).toBe(true);
  });
});
