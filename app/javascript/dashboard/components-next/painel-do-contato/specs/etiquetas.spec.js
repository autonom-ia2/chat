import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import BlocoEtiquetas from '../etiquetas/BlocoEtiquetas.vue';
import EtiquetasDaConversaDialog from '../etiquetas/EtiquetasDaConversaDialog.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
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
    expect(bloco.get('h3').text()).toBe('Etiquetas desta conversa');
    const itens = bloco.findAll('[data-test-id="etiqueta"]');
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
    // O leitor de tela ouve quais etiquetas a conversa tem, não só "mudar".
    expect(alvo.attributes('aria-label')).toBe(
      'Mudar as etiquetas desta conversa: vip'
    );
    expect(alvo.find('ul').exists()).toBe(false);
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
  // O Dialog é o de verdade (a lista só monta depois de abrir); a lista também é
  // a de verdade (LabelDropdown). Só o teleporte e o <dialog> nativo são fingidos.
  const AddLabelStub = {
    emits: ['close'],
    template: '<div data-criar-etiqueta />',
  };

  beforeEach(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  const montarEscolha = ({
    etiquetas = ['vip'],
    papel = 'agent',
    permissoes = [],
    erro = false,
    carregando = false,
    respostaManual = false,
  } = {}) => {
    const pendentes = [];
    const apoio = criarStore({
      conversaSelecionada: CONVERSA,
      etiquetasDaConta: ETIQUETAS_DA_CONTA,
      etiquetasDaConversa: { 42: etiquetas },
      uiEtiquetas: { isFetching: carregando },
      papel,
      permissoes,
      respostas: {
        // Imita o servidor: grava a lista pedida (ou falha) quando responde.
        'conversationLabels/update': (payload, r) => {
          const responder = () => {
            if (!erro) r.etiquetasDaConversa = { 42: payload.labels };
            r.uiEtiquetas = { isError: erro };
          };
          if (!respostaManual) return responder();
          return new Promise(resolve => {
            pendentes.push(() => {
              responder();
              resolve();
            });
          });
        },
      },
    });
    const wrapper = mount(EtiquetasDaConversaDialog, {
      attachTo: document.body,
      global: {
        plugins: [apoio.store, criarI18n()],
        stubs: {
          TeleportWithDirection: { template: '<div><slot /></div>' },
          teleport: true,
          'woot-dropdown-menu': { template: '<ul><slot /></ul>' },
          'woot-dropdown-item': { template: '<li><slot /></li>' },
          'woot-modal': { template: '<div data-modal><slot /></div>' },
          AddLabelModal: AddLabelStub,
        },
      },
    });
    const responderTodas = async () => {
      while (pendentes.length) {
        pendentes.shift()();
        // eslint-disable-next-line no-await-in-loop
        await flushPromises();
      }
    };
    return { wrapper, responderTodas, ...apoio };
  };

  const abrirEscolha = async opcoes => {
    const montado = montarEscolha(opcoes);
    montado.wrapper.vm.abrir();
    await flushPromises();
    return montado;
  };
  const nomes = wrapper =>
    wrapper.findAll('li button').map(botao => botao.text());
  const tocar = (wrapper, nome) =>
    wrapper
      .findAll('li button')
      .find(botao => botao.text() === nome)
      .trigger('click');
  const marcadas = wrapper =>
    wrapper
      .findAll('li button')
      // O item marcado leva o ícone de ✓ (LabelDropdownItem).
      .filter(botao => botao.attributes('icon') === 'i-lucide-circle-check')
      .map(botao => botao.text());

  it('a lista só monta ao abrir, com a busca em foco', async () => {
    const { wrapper } = montarEscolha();
    expect(wrapper.find('input.search-input').exists()).toBe(false);
    wrapper.vm.abrir();
    await flushPromises();
    expect(HTMLDialogElement.prototype.showModal).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('Etiquetas desta conversa');
    expect(wrapper.text()).toContain('Toque numa etiqueta para pôr ou tirar.');
    expect(document.activeElement).toBe(
      wrapper.get('input.search-input').element
    );
    expect(marcadas(wrapper)).toEqual(['vip']);
  });

  it('as que a conversa tem vêm primeiro, e a ordem não muda com os toques', async () => {
    const { wrapper } = await abrirEscolha({
      etiquetas: ['boleto', 'retorno'],
    });
    expect(nomes(wrapper)).toEqual(['retorno', 'boleto', 'vip']);
    await tocar(wrapper, 'vip');
    await flushPromises();
    await tocar(wrapper, 'retorno');
    await flushPromises();
    expect(marcadas(wrapper)).toEqual(['boleto', 'vip']);
    expect(nomes(wrapper)).toEqual(['retorno', 'boleto', 'vip']);
  });

  it('dois toques seguidos: a segunda gravação leva as duas etiquetas', async () => {
    const { wrapper, acoes, responderTodas } = await abrirEscolha({
      respostaManual: true,
    });
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'boleto');
    // A marca aparece na hora, antes de o servidor responder.
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno', 'boleto']);
    await responderTodas();
    expect(acoes).toEqual([
      [
        'conversationLabels/update',
        { conversationId: 42, labels: ['vip', 'retorno'] },
      ],
      [
        'conversationLabels/update',
        { conversationId: 42, labels: ['vip', 'retorno', 'boleto'] },
      ],
    ]);
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno', 'boleto']);
  });

  it('pôr e tirar etiqueta usam a action de sempre, com a conversa aberta', async () => {
    const { wrapper, acoes } = await abrirEscolha({
      etiquetas: ['vip', 'retorno'],
    });
    await tocar(wrapper, 'boleto');
    await flushPromises();
    await tocar(wrapper, 'vip');
    await flushPromises();
    expect(acoes).toEqual([
      [
        'conversationLabels/update',
        { conversationId: 42, labels: ['vip', 'retorno', 'boleto'] },
      ],
      [
        'conversationLabels/update',
        { conversationId: 42, labels: ['retorno', 'boleto'] },
      ],
    ]);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('erro ao salvar: avisa em frase simples e volta ao que está gravado', async () => {
    const { wrapper } = await abrirEscolha({ erro: true });
    await tocar(wrapper, 'boleto');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar a etiqueta. Tente de novo.'
    );
    expect(marcadas(wrapper)).toEqual(['vip']);
  });

  it('enquanto as etiquetas da conversa carregam, não dá para tocar', async () => {
    const { wrapper, dados } = await abrirEscolha({ carregando: true });
    expect(wrapper.find('[data-test-id="etiquetas-carregando"]').exists()).toBe(
      true
    );
    expect(wrapper.find('li button').exists()).toBe(false);
    dados.uiEtiquetas = { isFetching: false };
    await flushPromises();
    expect(nomes(wrapper)).toEqual(['vip', 'retorno', 'boleto']);
  });

  it('a lista não oferece criar etiqueta lá dentro', async () => {
    const { wrapper } = await abrirEscolha({
      papel: 'administrator',
      permissoes: ['administrator'],
    });
    // Lá dentro, a janela de criar ficaria presa ao <dialog>: cria-se pelo rodapé.
    expect(wrapper.findComponent(LabelDropdown).props('allowCreation')).toBe(
      false
    );
  });

  it('criar etiqueta só para quem administra etiquetas', async () => {
    const semPermissao = await abrirEscolha();
    expect(
      semPermissao.wrapper.find('[data-test-id="criar-etiqueta"]').exists()
    ).toBe(false);
    semPermissao.wrapper.unmount();
    const admin = await abrirEscolha({
      papel: 'administrator',
      permissoes: ['administrator'],
    });
    expect(admin.wrapper.find('[data-test-id="criar-etiqueta"]').exists()).toBe(
      true
    );
    admin.wrapper.unmount();
    const comChave = await abrirEscolha({
      permissoes: ['conversation_manage', 'label_manage'],
    });
    expect(
      comChave.wrapper.find('[data-test-id="criar-etiqueta"]').exists()
    ).toBe(true);
  });

  it('criar etiqueta fecha a escolha, abre a janela por fora e depois volta', async () => {
    const { wrapper } = await abrirEscolha({
      papel: 'administrator',
      permissoes: ['administrator'],
    });
    await wrapper.get('[data-test-id="criar-etiqueta"]').trigger('click');
    await flushPromises();
    expect(HTMLDialogElement.prototype.close).toHaveBeenCalled();
    expect(wrapper.find('input.search-input').exists()).toBe(false);
    const janela = wrapper.findComponent(AddLabelStub);
    expect(janela.exists()).toBe(true);
    janela.vm.$emit('close');
    await flushPromises();
    expect(wrapper.findComponent(AddLabelStub).exists()).toBe(false);
    expect(HTMLDialogElement.prototype.showModal).toHaveBeenCalledTimes(2);
    expect(wrapper.find('input.search-input').exists()).toBe(true);
  });
});
