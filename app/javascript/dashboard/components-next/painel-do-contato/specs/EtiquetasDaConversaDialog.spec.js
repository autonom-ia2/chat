import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import EtiquetasAPI from 'dashboard/api/etiquetasDaConversa';
import ConversationAPI from 'dashboard/api/conversations';
import conversationLabels from 'dashboard/store/modules/conversationLabels';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import EtiquetasDaConversaDialog from '../etiquetas/EtiquetasDaConversaDialog.vue';
import { esquecerTudo } from '../etiquetas/useEtiquetasDaConversa';
import { criarI18n, criarStore } from './apoio';

// #2202 (PR 3) — a escolha "Etiquetas desta conversa". Cada toque manda ao
// servidor só a intenção (pôr ou tirar UMA etiqueta), e o servidor aplica sobre
// o que a conversa tem; a resposta entra no store de verdade (conversationLabels).
// As duas janelas (⋯ do topo e bloco do painel) mostram as mesmas marcas.
vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));
vi.mock('dashboard/api/etiquetasDaConversa', () => ({
  default: { alterar: vi.fn() },
}));
vi.mock('dashboard/api/conversations', () => ({
  default: { getLabels: vi.fn() },
}));

enableAutoUnmount(afterEach);

const CONVERSA = { id: 42, inbox_id: 1, meta: {} };
const ETIQUETAS_DA_CONTA = [
  { id: 1, title: 'vip', color: '#ff0000' },
  { id: 2, title: 'retorno', color: '#00aa00' },
  { id: 3, title: 'boleto', color: '#0000ff' },
];
const AddLabelStub = {
  props: ['prefillTitle'],
  emits: ['close'],
  template: '<div data-criar-etiqueta />',
};
const DuasJanelas = {
  components: { EtiquetasDaConversaDialog },
  template:
    '<div><EtiquetasDaConversaDialog ref="topo" /><EtiquetasDaConversaDialog ref="bloco" /></div>',
};

// O servidor de mentira: guarda as etiquetas de cada conversa e responde quando
// o spec manda, aplicando a intenção sobre o que tem na hora (como o lock real).
const criarServidor = gravadas => {
  const etiquetas = structuredClone(gravadas);
  const fila = [];
  EtiquetasAPI.alterar.mockImplementation(
    (id, { por = [], tirar = [] }) =>
      new Promise((resolve, reject) => {
        fila.push({ id, por, tirar, resolve, reject });
      })
  );
  const responder = async ({ falha = false } = {}) => {
    const pedido = fila.shift();
    if (falha) {
      pedido.reject(new Error('timeout of 15000ms exceeded'));
    } else {
      const ficam = (etiquetas[pedido.id] || []).filter(
        titulo => !pedido.tirar.includes(titulo)
      );
      etiquetas[pedido.id] = [
        ...ficam,
        ...pedido.por.filter(titulo => !ficam.includes(titulo)),
      ];
      pedido.resolve({ data: { payload: [...etiquetas[pedido.id]] } });
    }
    await flushPromises();
  };
  const responderTodas = async () => {
    while (fila.length) {
      // eslint-disable-next-line no-await-in-loop
      await responder();
    }
  };
  return { etiquetas, fila, responder, responderTodas };
};

const montar = ({
  gravadas = { 42: ['vip'] },
  registros = gravadas,
  papel = 'agent',
  permissoes = [],
  componente = EtiquetasDaConversaDialog,
} = {}) => {
  const servidor = criarServidor(gravadas);
  const apoio = criarStore(
    {
      conversaSelecionada: CONVERSA,
      etiquetasDaConta: ETIQUETAS_DA_CONTA,
      papel,
      permissoes,
    },
    {},
    {
      conversationLabels: {
        ...conversationLabels,
        state: () => ({
          records: structuredClone(registros),
          uiFlags: { isFetching: false, isUpdating: false, isError: false },
        }),
      },
    }
  );
  const wrapper = mount(componente, {
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
  return { wrapper, servidor, ...apoio };
};

const abrirCom = async (opcoes, devolverFoco) => {
  const montado = montar(opcoes);
  montado.wrapper.vm.abrir(devolverFoco);
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
// O item marcado leva o ícone de ✓ (LabelDropdownItem).
const marcadas = wrapper =>
  wrapper
    .findAll('li button')
    .filter(botao => botao.attributes('icon') === 'i-lucide-circle-check')
    .map(botao => botao.text());
const gravadasNoStore = (store, id) =>
  store.getters['conversationLabels/getConversationLabels'](id);
const trocarPara = async (dados, id) => {
  dados.conversaSelecionada = { ...CONVERSA, id };
  await flushPromises();
};

beforeEach(() => {
  vi.clearAllMocks();
  esquecerTudo();
  HTMLDialogElement.prototype.showModal = vi.fn();
  HTMLDialogElement.prototype.close = vi.fn();
});

describe('EtiquetasDaConversaDialog — abrir e mostrar', () => {
  it('a lista só monta ao abrir, com a busca em foco', async () => {
    const { wrapper } = montar();
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
    const { wrapper, servidor } = await abrirCom({
      gravadas: { 42: ['boleto', 'retorno'] },
    });
    expect(nomes(wrapper)).toEqual(['retorno', 'boleto', 'vip']);
    await tocar(wrapper, 'vip');
    await tocar(wrapper, 'retorno');
    await servidor.responderTodas();
    expect(marcadas(wrapper)).toEqual(['boleto', 'vip']);
    expect(nomes(wrapper)).toEqual(['retorno', 'boleto', 'vip']);
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

  it('a caixa da busca cresce com o campo de 44 px', async () => {
    const { wrapper } = await abrirCom();
    const lista = wrapper.get('[data-test-id="lista-de-etiquetas"]');
    expect(lista.classes()).toContain(
      '[&_div:has(>.search-input)]:!max-h-none'
    );
    expect(lista.classes()).toContain('[&_.search-input]:!min-h-11');
  });

  it('a lista não oferece criar etiqueta lá dentro', async () => {
    const { wrapper } = await abrirCom({
      papel: 'administrator',
      permissoes: ['administrator'],
    });
    // Lá dentro, a janela de criar ficaria presa ao <dialog>: cria-se pelo rodapé.
    expect(wrapper.findComponent(LabelDropdown).props('allowCreation')).toBe(
      false
    );
  });
});

describe('EtiquetasDaConversaDialog — cada toque é uma intenção', () => {
  it('pôr e tirar mandam só a etiqueta tocada, da conversa aberta', async () => {
    const { wrapper, servidor, store } = await abrirCom({
      gravadas: { 42: ['vip', 'retorno'] },
    });
    await tocar(wrapper, 'boleto');
    await tocar(wrapper, 'vip');
    await servidor.responderTodas();
    expect(EtiquetasAPI.alterar.mock.calls).toEqual([
      [42, { por: ['boleto'] }],
      [42, { tirar: ['vip'] }],
    ]);
    // A resposta do servidor entra no store pela mutation de sempre.
    expect(gravadasNoStore(store, 42)).toEqual(['retorno', 'boleto']);
    expect(marcadas(wrapper)).toEqual(['retorno', 'boleto']);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('dois toques seguidos: a marca aparece na hora e as duas ficam', async () => {
    const { wrapper, servidor } = await abrirCom();
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'boleto');
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno', 'boleto']);
    await servidor.responderTodas();
    expect(servidor.etiquetas[42]).toEqual(['vip', 'retorno', 'boleto']);
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno', 'boleto']);
  });

  it('etiqueta que a conta já não tem na lista fica na conversa', async () => {
    // "antiga" foi apagada das etiquetas da conta, mas a conversa ainda a tem.
    const { wrapper, servidor, store } = await abrirCom({
      gravadas: { 42: ['antiga', 'vip'] },
    });
    expect(nomes(wrapper)).not.toContain('antiga');
    await tocar(wrapper, 'boleto');
    await tocar(wrapper, 'vip');
    await servidor.responderTodas();
    expect(EtiquetasAPI.alterar.mock.calls).toEqual([
      [42, { por: ['boleto'] }],
      [42, { tirar: ['vip'] }],
    ]);
    expect(gravadasNoStore(store, 42)).toEqual(['antiga', 'boleto']);
  });

  it('mudança de outra pessoa no meio-tempo não é apagada', async () => {
    const { wrapper, servidor } = await abrirCom();
    await tocar(wrapper, 'retorno');
    // Outra pessoa (outra aba, outro computador) põe "boleto" pela rota de sempre.
    servidor.etiquetas[42] = [...servidor.etiquetas[42], 'boleto'];
    await tocar(wrapper, 'vip');
    await servidor.responderTodas();
    expect(servidor.etiquetas[42]).toEqual(['boleto', 'retorno']);
    expect(marcadas(wrapper)).toEqual(['retorno', 'boleto']);
  });

  it('tempo real atrasado no meio da fila não faz a terceira apagar a segunda', async () => {
    // Achado 2: um evento velho do tempo real trocava o store por uma lista sem
    // a 2ª etiqueta, e a 3ª gravação (lista inteira) a apagava.
    const { wrapper, servidor, store } = await abrirCom();
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'boleto');
    await servidor.responder();
    await servidor.responder();
    await tocar(wrapper, 'vip');
    store.dispatch('conversationLabels/setConversationLabel', {
      id: 42,
      data: ['vip', 'retorno'],
    });
    await flushPromises();
    await servidor.responderTodas();
    expect(EtiquetasAPI.alterar.mock.calls[2]).toEqual([
      42,
      { tirar: ['vip'] },
    ]);
    expect(servidor.etiquetas[42]).toEqual(['retorno', 'boleto']);
    expect(gravadasNoStore(store, 42)).toEqual(['retorno', 'boleto']);
  });
});

describe('EtiquetasDaConversaDialog — erro', () => {
  it('erro desta chamada: avisa em frase simples e volta ao que está gravado', async () => {
    const { wrapper, servidor } = await abrirCom();
    await tocar(wrapper, 'boleto');
    expect(marcadas(wrapper)).toEqual(['vip', 'boleto']);
    await servidor.responder({ falha: true });
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar a etiqueta. Tente de novo.'
    );
    expect(marcadas(wrapper)).toEqual(['vip']);
  });

  it('a flag de erro do store (de outra gravação) não vira aviso aqui', async () => {
    // Achado 3: o erro vinha da flag global isError, que outra tela pode ligar.
    const { wrapper, servidor, store } = await abrirCom();
    store.commit('conversationLabels/SET_CONVERSATION_LABELS_UI_FLAG', {
      isError: true,
    });
    await tocar(wrapper, 'boleto');
    await servidor.responderTodas();
    expect(useAlert).not.toHaveBeenCalled();
    expect(marcadas(wrapper)).toEqual(['vip', 'boleto']);
  });

  it('erro no meio da fila: só a que falhou sai, a próxima segue', async () => {
    const { wrapper, servidor } = await abrirCom();
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'boleto');
    await servidor.responder({ falha: true });
    expect(useAlert).toHaveBeenCalledTimes(1);
    // "retorno" falhou e sai da tela; "boleto" ainda está a caminho.
    expect(marcadas(wrapper)).toEqual(['vip', 'boleto']);
    await servidor.responderTodas();
    expect(EtiquetasAPI.alterar.mock.calls[1]).toEqual([
      42,
      { por: ['boleto'] },
    ]);
    expect(marcadas(wrapper)).toEqual(['vip', 'boleto']);
    expect(useAlert).toHaveBeenCalledTimes(1);
  });
});

describe('EtiquetasDaConversaDialog — sem o registro das etiquetas', () => {
  it('mostra carregando, pede as etiquetas e não grava nada até chegarem', async () => {
    // Achado 4: sem registro, a lista vinha vazia e um toque apagava as que a
    // conversa tinha.
    let entregar;
    ConversationAPI.getLabels.mockReturnValue(
      new Promise(resolve => {
        entregar = resolve;
      })
    );
    const { wrapper } = await abrirCom({
      gravadas: { 42: ['vip'] },
      registros: {},
    });
    const carregando = wrapper.get('[data-test-id="etiquetas-carregando"]');
    expect(carregando.attributes('role')).toBe('status');
    expect(carregando.attributes('aria-label')).toBe('Carregando');
    expect(wrapper.find('li button').exists()).toBe(false);
    expect(ConversationAPI.getLabels).toHaveBeenCalledWith(42);

    entregar({ data: { payload: ['vip'] } });
    await flushPromises();
    expect(nomes(wrapper)).toEqual(['vip', 'retorno', 'boleto']);
    expect(marcadas(wrapper)).toEqual(['vip']);
    expect(EtiquetasAPI.alterar).not.toHaveBeenCalled();
  });

  it('as que a conversa tem vêm primeiro também quando o registro chega depois de abrir', async () => {
    // Revisão #2290: a ordem era pega ao abrir, com o registro ainda vazio.
    let entregar;
    ConversationAPI.getLabels.mockReturnValue(
      new Promise(resolve => {
        entregar = resolve;
      })
    );
    const { wrapper, servidor } = await abrirCom({
      gravadas: { 42: ['boleto'] },
      registros: {},
    });

    entregar({ data: { payload: ['boleto'] } });
    await flushPromises();
    expect(nomes(wrapper)).toEqual(['boleto', 'vip', 'retorno']);

    // Depois de chegar, a ordem fica parada com os toques.
    await tocar(wrapper, 'retorno');
    await servidor.responderTodas();
    expect(marcadas(wrapper)).toEqual(['boleto', 'retorno']);
    expect(nomes(wrapper)).toEqual(['boleto', 'vip', 'retorno']);
  });

  it('a busca falhou: avisa na janela, sem carregar para sempre, e tentar de novo traz a lista', async () => {
    // Revisão #2290: a action do store engolia o erro e o carregando não saía.
    ConversationAPI.getLabels.mockRejectedValueOnce(new Error('Network Error'));
    const { wrapper } = await abrirCom({
      gravadas: { 42: ['retorno'] },
      registros: {},
    });

    expect(wrapper.find('[data-test-id="etiquetas-carregando"]').exists()).toBe(
      false
    );
    expect(wrapper.find('li button').exists()).toBe(false);
    const aviso = wrapper.get('[data-test-id="etiquetas-falhou"]');
    expect(aviso.attributes('role')).toBe('alert');
    expect(aviso.text()).toContain(
      'Não deu para carregar as etiquetas desta conversa.'
    );
    const tentar = wrapper.get('[data-test-id="etiquetas-tentar-de-novo"]');
    expect(tentar.text()).toBe('Tentar de novo');
    expect(tentar.classes()).toContain('!min-h-11');

    ConversationAPI.getLabels.mockResolvedValueOnce({
      data: { payload: ['retorno'] },
    });
    await tentar.trigger('click');
    await flushPromises();

    expect(ConversationAPI.getLabels).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-test-id="etiquetas-falhou"]').exists()).toBe(
      false
    );
    expect(nomes(wrapper)).toEqual(['retorno', 'vip', 'boleto']);
    expect(marcadas(wrapper)).toEqual(['retorno']);
    expect(EtiquetasAPI.alterar).not.toHaveBeenCalled();
  });

  it('tentar de novo mostra carregando enquanto espera', async () => {
    ConversationAPI.getLabels.mockRejectedValueOnce(new Error('Network Error'));
    const { wrapper } = await abrirCom({ registros: {} });
    ConversationAPI.getLabels.mockReturnValueOnce(new Promise(() => {}));

    await wrapper
      .get('[data-test-id="etiquetas-tentar-de-novo"]')
      .trigger('click');

    expect(wrapper.find('[data-test-id="etiquetas-carregando"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-test-id="etiquetas-falhou"]').exists()).toBe(
      false
    );
  });
});

describe('EtiquetasDaConversaDialog — trocar de conversa', () => {
  it('no meio da fila, cada gravação vai para a conversa do toque', async () => {
    const { wrapper, dados, servidor, store } = await abrirCom({
      gravadas: { 42: ['vip'], 43: ['boleto'] },
    });
    await tocar(wrapper, 'retorno');
    await tocar(wrapper, 'boleto');
    // Alt+K com a janela aberta: troca a conversa.
    await trocarPara(dados, 43);
    expect(HTMLDialogElement.prototype.close).toHaveBeenCalled();
    expect(wrapper.find('input.search-input').exists()).toBe(false);

    await servidor.responderTodas();
    expect(EtiquetasAPI.alterar.mock.calls).toEqual([
      [42, { por: ['retorno'] }],
      [42, { por: ['boleto'] }],
    ]);
    expect(gravadasNoStore(store, 42)).toEqual(['vip', 'retorno', 'boleto']);
    expect(gravadasNoStore(store, 43)).toEqual(['boleto']);

    // Na conversa nova, a escolha mostra as etiquetas dela.
    wrapper.vm.abrir();
    await flushPromises();
    expect(marcadas(wrapper)).toEqual(['boleto']);
  });

  it('as marcas pendentes de uma conversa não somem na troca nem aparecem na outra', async () => {
    // Achado 5: a troca limpava as pendentes de todas as conversas.
    const { wrapper, dados, servidor } = await abrirCom({
      gravadas: { 42: ['vip'], 43: [] },
    });
    await tocar(wrapper, 'retorno');
    await trocarPara(dados, 43);
    wrapper.vm.abrir();
    await flushPromises();
    expect(marcadas(wrapper)).toEqual([]);
    await trocarPara(dados, 42);
    wrapper.vm.abrir();
    await flushPromises();
    // A marca de "retorno" segue na tela antes de o servidor responder…
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno']);
    await servidor.responderTodas();
    // …e fica quando ele grava.
    expect(marcadas(wrapper)).toEqual(['vip', 'retorno']);
  });

  it('com a janela aberta, fecha sem devolver o foco', async () => {
    const devolverFoco = vi.fn();
    const { dados } = await abrirCom({}, devolverFoco);
    await trocarPara(dados, 43);
    expect(HTMLDialogElement.prototype.close).toHaveBeenCalled();
    expect(devolverFoco).not.toHaveBeenCalled();
  });

  it('com a janela fechada, não mexe no foco', async () => {
    const devolverFoco = vi.fn();
    const { wrapper, dados } = await abrirCom({}, devolverFoco);
    await wrapper.get('[data-test-id="etiquetas-pronto"]').trigger('click');
    await flushPromises();
    await trocarPara(dados, 43);
    expect(devolverFoco).toHaveBeenCalledTimes(1);
  });
});

describe('EtiquetasDaConversaDialog — as duas janelas', () => {
  // Achado 1 (ALTA): o ⋯ do topo e o bloco do painel tinham cada um a sua fila,
  // e a gravação de um apagava a etiqueta do outro.
  const abrirAsDuas = async opcoes => {
    const montado = montar({ ...opcoes, componente: DuasJanelas });
    const [topo, bloco] = montado.wrapper.findAllComponents(
      EtiquetasDaConversaDialog
    );
    topo.vm.abrir();
    bloco.vm.abrir();
    await flushPromises();
    return { ...montado, topo, bloco };
  };

  it('as duas mostram as mesmas marcas, inclusive as que estão a caminho', async () => {
    const { topo, bloco, servidor } = await abrirAsDuas();
    await tocar(topo, 'retorno');
    expect(marcadas(topo)).toEqual(['vip', 'retorno']);
    expect(marcadas(bloco)).toEqual(['vip', 'retorno']);
    await tocar(bloco, 'vip');
    expect(marcadas(topo)).toEqual(['retorno']);
    expect(marcadas(bloco)).toEqual(['retorno']);
    await servidor.responderTodas();
    expect(marcadas(topo)).toEqual(['retorno']);
    expect(marcadas(bloco)).toEqual(['retorno']);
  });

  it('uma não apaga a etiqueta que a outra pôs', async () => {
    const { topo, bloco, servidor, store } = await abrirAsDuas();
    await tocar(topo, 'retorno');
    await tocar(bloco, 'boleto');
    await servidor.responderTodas();
    expect(servidor.etiquetas[42]).toEqual(['vip', 'retorno', 'boleto']);
    expect(gravadasNoStore(store, 42)).toEqual(['vip', 'retorno', 'boleto']);
    expect(marcadas(topo)).toEqual(['vip', 'retorno', 'boleto']);
    expect(marcadas(bloco)).toEqual(['vip', 'retorno', 'boleto']);
  });
});

describe('EtiquetasDaConversaDialog — teclado, foco e criar', () => {
  it('Enter na busca não põe nem tira etiqueta', async () => {
    const { wrapper } = await abrirCom();
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
    expect(EtiquetasAPI.alterar).not.toHaveBeenCalled();
    // No botão da etiqueta, Enter continua sendo o toque pelo teclado.
    const noBotao = enter();
    wrapper.get('li button').element.dispatchEvent(noBotao);
    expect(noBotao.defaultPrevented).toBe(false);
  });

  it('ao fechar, o foco volta para quem abriu', async () => {
    const devolverFoco = vi.fn();
    const { wrapper } = await abrirCom({}, devolverFoco);
    await wrapper.get('[data-test-id="etiquetas-pronto"]').trigger('click');
    await flushPromises();
    expect(devolverFoco).toHaveBeenCalledTimes(1);
  });

  it('criar etiqueta só para quem administra etiquetas', async () => {
    const semPermissao = await abrirCom();
    expect(
      semPermissao.wrapper.find('[data-test-id="criar-etiqueta"]').exists()
    ).toBe(false);
    semPermissao.wrapper.unmount();
    const admin = await abrirCom({
      papel: 'administrator',
      permissoes: ['administrator'],
    });
    expect(admin.wrapper.find('[data-test-id="criar-etiqueta"]').exists()).toBe(
      true
    );
    admin.wrapper.unmount();
    const comChave = await abrirCom({
      permissoes: ['conversation_manage', 'label_manage'],
    });
    expect(
      comChave.wrapper.find('[data-test-id="criar-etiqueta"]').exists()
    ).toBe(true);
  });

  it('criar leva o texto da busca, abre por fora e a escolha volta; o foco só no fim', async () => {
    const devolverFoco = vi.fn();
    const { wrapper } = await abrirCom(
      { papel: 'administrator', permissoes: ['administrator'] },
      devolverFoco
    );
    await wrapper.get('input.search-input').setValue('novo');
    await wrapper.get('[data-test-id="criar-etiqueta"]').trigger('click');
    await flushPromises();
    expect(HTMLDialogElement.prototype.close).toHaveBeenCalled();
    expect(wrapper.find('input.search-input').exists()).toBe(false);
    const janela = wrapper.findComponent(AddLabelStub);
    expect(janela.props('prefillTitle')).toBe('novo');
    expect(devolverFoco).not.toHaveBeenCalled();
    janela.vm.$emit('close');
    await flushPromises();
    expect(wrapper.findComponent(AddLabelStub).exists()).toBe(false);
    expect(HTMLDialogElement.prototype.showModal).toHaveBeenCalledTimes(2);
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
});
