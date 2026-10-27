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

const montarBloco = ({
  etiquetas = [],
  podeOperar = true,
  focarPainel = vi.fn(),
} = {}) => {
  const apoio = criarStore({
    conversaSelecionada: CONVERSA,
    etiquetasDaConta: ETIQUETAS_DA_CONTA,
    etiquetasDaConversa: { 42: etiquetas },
  });
  const wrapper = mount(BlocoEtiquetas, {
    attachTo: document.body,
    props: { podeOperar, focarPainel },
    global: {
      plugins: [apoio.store, criarI18n()],
      stubs: { EtiquetasDaConversaDialog: EscolhaStub },
    },
  });
  return { wrapper, focarPainel, ...apoio };
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

  it('ao fechar a escolha, o foco volta para o bloco', async () => {
    const { wrapper, focarPainel } = montarBloco({ etiquetas: ['vip'] });
    const alvo = wrapper.get('[data-test-id="etiquetas-da-conversa"]');
    await alvo.trigger('click');
    const [devolverFoco] = abrir.mock.calls[0];
    devolverFoco();
    expect(document.activeElement).toBe(alvo.element);
    expect(focarPainel).not.toHaveBeenCalled();
  });

  it('se o bloco sumiu (tirou a última), o foco vai para o painel', async () => {
    const { wrapper, dados, focarPainel } = montarBloco({ etiquetas: ['vip'] });
    await wrapper
      .get('[data-test-id="etiquetas-da-conversa"]')
      .trigger('click');
    const [devolverFoco] = abrir.mock.calls[0];
    dados.etiquetasDaConversa = { 42: [] };
    await flushPromises();
    devolverFoco();
    expect(focarPainel).toHaveBeenCalledTimes(1);
  });
});

describe('EtiquetasDaConversaDialog', () => {
  // O Dialog é o de verdade (a lista só monta depois de abrir); a lista também é
  // a de verdade (LabelDropdown). Só o teleporte e o <dialog> nativo são fingidos.
  const AddLabelStub = {
    props: ['prefillTitle'],
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

describe('EtiquetasDaConversaDialog — fila de toques (revisão do #2290)', () => {
  const AddLabelStub = {
    props: ['prefillTitle'],
    emits: ['close'],
    template: '<div data-criar-etiqueta />',
  };

  beforeEach(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  const montar = ({
    etiquetas = ['vip'],
    outrasConversas = {},
    erro = false,
    rejeita = false,
    papel = 'agent',
    permissoes = [],
  } = {}) => {
    const pendentes = [];
    const falha = vez => (Array.isArray(erro) ? Boolean(erro[vez]) : erro);
    let vezes = 0;
    const apoio = criarStore({
      conversaSelecionada: CONVERSA,
      etiquetasDaConta: ETIQUETAS_DA_CONTA,
      etiquetasDaConversa: { 42: etiquetas, ...outrasConversas },
      papel,
      permissoes,
      respostas: {
        // Imita o servidor: responde quando o spec manda, gravando a lista pedida
        // na conversa pedida (ou falhando).
        'conversationLabels/update': (payload, r) => {
          if (rejeita) return Promise.reject(new Error('rede'));
          const comErro = falha(vezes);
          vezes += 1;
          return new Promise(resolve => {
            pendentes.push(() => {
              if (!comErro)
                r.etiquetasDaConversa = {
                  ...r.etiquetasDaConversa,
                  [payload.conversationId]: payload.labels,
                };
              r.uiEtiquetas = { isError: comErro };
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
    const responderUma = async () => {
      pendentes.shift()();
      await flushPromises();
    };
    const responderTodas = async () => {
      while (pendentes.length) {
        // eslint-disable-next-line no-await-in-loop
        await responderUma();
      }
    };
    return { wrapper, responderUma, responderTodas, pendentes, ...apoio };
  };

  const abrirCom = async (opcoes, devolverFoco) => {
    const montado = montar(opcoes);
    montado.wrapper.vm.abrir(devolverFoco);
    await flushPromises();
    return montado;
  };
  const tocar = (wrapper, nome) =>
    wrapper
      .findAll('li button')
      .find(botao => botao.text() === nome)
      .trigger('click');
  const marcadas = wrapper =>
    wrapper
      .findAll('li button')
      .filter(botao => botao.attributes('icon') === 'i-lucide-circle-check')
      .map(botao => botao.text());
  const trocarPara = async (dados, id) => {
    dados.conversaSelecionada = { ...CONVERSA, id };
    await flushPromises();
  };

  it('trocar de conversa no meio da fila: cada gravação vai para a conversa do toque', async () => {
    // Achado ALTA: a fila lia a conversa na hora em que a vez chegava.
    const { wrapper, dados, acoes, responderTodas } = await abrirCom({
      outrasConversas: { 43: ['boleto'] },
    });
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'boleto');
    // Alt+K com a janela aberta: troca a conversa.
    await trocarPara(dados, 43);
    expect(HTMLDialogElement.prototype.close).toHaveBeenCalled();
    expect(wrapper.find('input.search-input').exists()).toBe(false);

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
    expect(dados.etiquetasDaConversa[43]).toEqual(['boleto']);

    // Na conversa nova, a escolha mostra as etiquetas dela.
    wrapper.vm.abrir();
    await flushPromises();
    expect(marcadas(wrapper)).toEqual(['boleto']);
  });

  it('trocar de conversa larga as marcas pendentes da tela', async () => {
    const { wrapper, dados, responderTodas } = await abrirCom();
    await tocar(wrapper, 'retorno');
    await trocarPara(dados, 43);
    await trocarPara(dados, 42);
    wrapper.vm.abrir();
    await flushPromises();
    // A marca de "retorno" não volta antes do servidor responder…
    expect(marcadas(wrapper)).toEqual(['vip']);
    await responderTodas();
    // …e aparece quando ele grava.
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno']);
  });

  it('mudança de outra pessoa durante a fila não é apagada', async () => {
    const { wrapper, dados, acoes, pendentes } = await abrirCom();
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'vip');
    // O servidor grava a primeira; logo depois chega, em tempo real, a etiqueta
    // "boleto" que outra pessoa pôs — antes de a segunda gravação sair.
    pendentes.shift()();
    dados.etiquetasDaConversa = { 42: ['vip', 'retorno', 'boleto'] };
    await flushPromises();
    expect(marcadas(wrapper)).toEqual(['retorno', 'boleto']);
    expect(acoes[1]).toEqual([
      'conversationLabels/update',
      { conversationId: 42, labels: ['retorno', 'boleto'] },
    ]);
  });

  it('erro no meio da fila: a tela volta ao que está gravado e a próxima parte dele', async () => {
    const { wrapper, acoes, responderUma, responderTodas } = await abrirCom({
      erro: [true, false],
    });
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'boleto');
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno', 'boleto']);
    await responderUma();
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar a etiqueta. Tente de novo.'
    );
    // "retorno" falhou: sai da tela; "boleto" ainda está a caminho.
    expect(marcadas(wrapper)).toEqual(['vip', 'boleto']);
    await responderTodas();
    expect(acoes[1]).toEqual([
      'conversationLabels/update',
      { conversationId: 42, labels: ['vip', 'boleto'] },
    ]);
    expect(marcadas(wrapper)).toEqual(['vip', 'boleto']);
    expect(useAlert).toHaveBeenCalledTimes(1);
  });

  it('se a gravação estoura, avisa e a fila segue', async () => {
    const { wrapper, acoes } = await abrirCom({ rejeita: true });
    await tocar(wrapper, 'retorno');
    await flushPromises();
    await tocar(wrapper, 'boleto');
    await flushPromises();
    expect(acoes).toHaveLength(2);
    expect(useAlert).toHaveBeenCalledTimes(2);
    expect(marcadas(wrapper)).toEqual(['vip']);
  });

  it('Enter na busca não põe nem tira etiqueta', async () => {
    const { wrapper, acoes } = await abrirCom();
    const enter = () =>
      new KeyboardEvent('keydown', {
        key: 'Enter',
        bubbles: true,
        cancelable: true,
      });
    const naBusca = enter();
    wrapper.get('input.search-input').element.dispatchEvent(naBusca);
    await flushPromises();
    expect(naBusca.defaultPrevented).toBe(true);
    expect(acoes).toEqual([]);
    // No botão da etiqueta, Enter continua sendo o toque pelo teclado.
    const noBotao = enter();
    wrapper.get('li button').element.dispatchEvent(noBotao);
    expect(noBotao.defaultPrevented).toBe(false);
  });

  it('a caixa da busca cresce com o campo de 44 px', async () => {
    const { wrapper } = await abrirCom();
    const lista = wrapper.get('[data-test-id="lista-de-etiquetas"]');
    expect(lista.classes()).toContain(
      '[&_div:has(>.search-input)]:!max-h-none'
    );
    expect(lista.classes()).toContain('[&_.search-input]:!min-h-11');
  });

  it('os itens dizem ao leitor de tela se a etiqueta está posta', async () => {
    const { wrapper } = await abrirCom();
    const estados = wrapper
      .findAll('li button')
      .map(botao => [botao.text(), botao.attributes('aria-pressed')]);
    expect(estados).toEqual([
      ['vip', 'true'],
      ['retorno', 'false'],
      ['boleto', 'false'],
    ]);
  });

  it('ao fechar, o foco volta para quem abriu', async () => {
    const devolverFoco = vi.fn();
    const { wrapper } = await abrirCom({}, devolverFoco);
    await wrapper.get('[data-test-id="etiquetas-pronto"]').trigger('click');
    await flushPromises();
    expect(devolverFoco).toHaveBeenCalledTimes(1);
  });

  it('criar etiqueta leva o texto da busca e o foco só volta no fim', async () => {
    const devolverFoco = vi.fn();
    const { wrapper } = await abrirCom(
      { papel: 'administrator', permissoes: ['administrator'] },
      devolverFoco
    );
    await wrapper.get('input.search-input').setValue('novo');
    await wrapper.get('[data-test-id="criar-etiqueta"]').trigger('click');
    await flushPromises();
    const janela = wrapper.findComponent(AddLabelStub);
    expect(janela.props('prefillTitle')).toBe('novo');
    expect(devolverFoco).not.toHaveBeenCalled();
    janela.vm.$emit('close');
    await flushPromises();
    // A escolha volta aberta; o foco só volta quando ela fechar.
    expect(wrapper.find('input.search-input').exists()).toBe(true);
    expect(devolverFoco).not.toHaveBeenCalled();
    await wrapper.get('[data-test-id="etiquetas-pronto"]').trigger('click');
    await flushPromises();
    expect(devolverFoco).toHaveBeenCalledTimes(1);
  });

  it('trocou de conversa enquanto criava: a escolha não reabre e o foco volta', async () => {
    const devolverFoco = vi.fn();
    const { wrapper, dados } = await abrirCom(
      { papel: 'administrator', permissoes: ['administrator'] },
      devolverFoco
    );
    await wrapper.get('[data-test-id="criar-etiqueta"]').trigger('click');
    await flushPromises();
    await trocarPara(dados, 43);
    wrapper.findComponent(AddLabelStub).vm.$emit('close');
    await flushPromises();
    expect(HTMLDialogElement.prototype.showModal).toHaveBeenCalledTimes(1);
    expect(devolverFoco).toHaveBeenCalledTimes(1);
  });

  it('trocar de conversa com a escolha fechada não mexe no foco', async () => {
    const devolverFoco = vi.fn();
    const { wrapper, dados } = await abrirCom({}, devolverFoco);
    await wrapper.get('[data-test-id="etiquetas-pronto"]').trigger('click');
    await flushPromises();
    await trocarPara(dados, 43);
    expect(devolverFoco).toHaveBeenCalledTimes(1);
  });
});
