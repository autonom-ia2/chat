import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';
import {
  useAutonomiaGuideStore,
  motivoUtilizavel,
} from 'dashboard/store/modules/autonomiaGuide';
import AutonomiaGuideContainer from '../AutonomiaGuideContainer.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
// Espião estável: `useRouter()` roda de novo a cada teste, e um `vi.fn()`
// novo a cada chamada não deixaria como afirmar QUAL rota o clique pediu.
const { routerPush, rotaAtual } = vi.hoisted(() => ({
  routerPush: vi.fn(),
  rotaAtual: { name: 'home' },
}));
vi.mock('vue-router', () => ({
  useRoute: () => rotaAtual,
  // Rota real do registro do Guia (ex.: 'labels_list'): resolve de verdade, para os testes de
  // navegação (#636) poderem afirmar que o clique leva ao alvo certo.
  useRouter: () => ({ resolve: () => ({ matched: [{}] }), push: routerPush }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ref({ is_autonomia_guide_panel_open: true }),
    updateUISettings: vi.fn(),
  }),
}));
// A conta aberta: os testes de troca de conta mudam o valor.
let mockContaAtual;
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: true }));
    }
    if (getter === 'getCurrentAccountId') {
      mockContaAtual = mockContaAtual || ref(1);
      return mockContaAtual;
    }
    // `accounts/isFeatureEnabledonAccount`: as telas usadas nestes testes exigem recurso ligado
    // na conta (#636 usa rotas reais do registro, e a maioria tem `gate` de feature).
    return ref(() => true);
  },
}));
// #697 — sugestões da tela aberta, a partir dos artigos da Central.
vi.mock('dashboard/api/centralDeAjuda', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: { capitulos: [] } })) },
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: {
    chat: vi.fn(),
    resposta: vi.fn(),
    executarAcao: vi.fn(),
    enviarArquivo: vi.fn(),
    transcrever: vi.fn(),
    // #861 — sem conversa guardada, a não ser no teste que diz o contrário.
    conversaAtual: vi.fn(() => Promise.resolve({ data: {} })),
    conversa: vi.fn(),
    conversas: vi.fn(() => Promise.resolve({ data: { conversas: [] } })),
    apagarConversa: vi.fn(),
  },
}));

// #572 — a pergunta abre um pedido, e a resposta se busca depois.
const pedidoAberto = () =>
  AutonomiaGuideAPI.chat.mockResolvedValue({
    data: { id: 'pedido-1', status: 'pending' },
  });

// A tela espera entre uma busca e outra; o relógio de teste anda por ela.
const esperarUmaBusca = () => vi.advanceTimersByTimeAsync(1500);

const perguntar = async (wrapper, texto) => {
  const textarea = wrapper.find('textarea');
  await textarea.setValue(texto);
  await textarea.trigger('keydown', { key: 'Enter' });
  await flushPromises();
  return textarea;
};

const ACAO = {
  nome: 'criar_funil',
  dados: { nome: 'Vendas' },
  descricao: {
    frase: 'Vou criar o funil Vendas.',
    detalhe: 'criar_funil(nome: "Vendas")',
  },
};

// `t` é substituível (revisão #637 do PR): a maioria dos testes só precisa da CHAVE de volta, mas
// o teste de interpolação do rótulo (`AUTONOMIA_GUIDE.GO_TO_SCREEN_NAMED`) precisa do texto FINAL,
// com `{rotulo}`/`{titulo}`/`{numero}` substituídos — senão duas chaves diferentes ("Ir para: X" e
// "Ir para a tela 2") virariam a mesma string e o teste não provaria nada.
const mountGuide = ({ t = key => key } = {}) =>
  mount(AutonomiaGuideContainer, {
    attachTo: document.body,
    global: {
      mocks: { $t: t },
      directives: { onClickOutside: {}, dompurifyHtml: {} },
    },
  });

// Sem regex (proibido neste repositório): troca `{nome}` pelo valor via split/join.
const interpolar = (modelo, params) =>
  Object.entries(params || {}).reduce(
    (texto, [nome, valor]) => texto.split(`{${nome}}`).join(String(valor)),
    modelo
  );

// As MESMAS strings de `app/javascript/dashboard/i18n/locale/pt_BR/crm.json`, só para as chaves
// que os testes de interpolação usam — duplicar aqui é o preço de testar o texto final sem montar
// o vue-i18n de verdade.
const MENSAGENS_PT = {
  'AUTONOMIA_GUIDE.GO_TO_SCREEN_NAMED': 'Ir para: {rotulo}',
  'AUTONOMIA_GUIDE.GO_TO_SCREEN_NUMBERED': 'Ir para a tela {numero}',
  'AUTONOMIA_GUIDE.READ_ARTICLE_NAMED': 'Ler: {titulo}',
};

const tComInterpolacao = (chave, params) =>
  interpolar(MENSAGENS_PT[chave] || chave, params);

// Comparação EXATA, não `includes` (revisão #637 do PR): com `includes`, o botão
// "AUTONOMIA_GUIDE.GO_TO_SCREEN_NAMED" passaria também num `findByLabel(wrapper,
// 'AUTONOMIA_GUIDE.GO_TO_SCREEN')" — são chaves diferentes, e o teste não pegaria o rótulo trocado.
const findByLabel = (wrapper, chave) =>
  wrapper.findAll('button').find(botao => botao.text() === chave);

const comAcaoProposta = () => {
  const store = useAutonomiaGuideStore();
  store.addAssistantMessage({ content: 'Posso criar para você.', acao: ACAO });
  return store;
};

const ARTIGO = { ref: '02-04', titulo: 'Conectar o WhatsApp' };

const comArtigoLido = () => {
  const store = useAutonomiaGuideStore();
  store.addAssistantMessage({
    content: 'É em Configurações > Canais.',
    artigo: ARTIGO,
  });
  return store;
};

describe('AutonomiaGuideContainer', () => {
  let wrapper;

  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaGuideStore().reset();
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  // Revisão do #908: um áudio que esperava a vez não pode sair na conta seguinte.
  it('recomeça o composer ao trocar de conta, descartando gravação e áudio na espera', async () => {
    wrapper = mountGuide();
    await flushPromises();
    const antes = wrapper.findComponent({ name: 'GuideComposer' }).vm.$.uid;

    mockContaAtual.value = 2;
    await flushPromises();

    const depois = wrapper.findComponent({ name: 'GuideComposer' }).vm.$.uid;
    expect(depois).not.toBe(antes);
    mockContaAtual.value = 1;
    await flushPromises();
  });

  it('clears the input as soon as the question enters the thread', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'done', available: true, text: 'Assim.' },
    });
    wrapper = mountGuide();

    const textarea = await perguntar(wrapper, 'Como crio um funil?');

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledOnce();
    expect(textarea.element.value).toBe('');

    await esperarUmaBusca();
    await flushPromises();
    expect(useAutonomiaGuideStore().messages).toHaveLength(2);
  });

  // #857 — o arquivo anexado vai junto de cada pergunta da conversa.
  it('sends the attached files with the question', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.enviarArquivo.mockResolvedValue({
      data: { signed_id: 'arquivo-1', nome: 'leads.csv' },
    });
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'done', available: true, text: 'Li a planilha.' },
    });
    wrapper = mountGuide();

    const arquivo = new File(['nome'], 'leads.csv', { type: 'text/csv' });
    wrapper
      .findComponent({ name: 'GuideComposer' })
      .vm.$emit('anexar', arquivo);
    await flushPromises();
    await perguntar(wrapper, 'Resume a planilha');

    expect(AutonomiaGuideAPI.enviarArquivo).toHaveBeenCalledWith(arquivo);
    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledWith(
      expect.objectContaining({ arquivos: ['arquivo-1'] })
    );
  });

  // O Guia pode ler várias vezes antes de responder. Enquanto pensa, o pedido
  // está pendente, e a tela tem que continuar buscando — não desistir na
  // primeira nem mostrar resposta vazia.
  it('keeps asking while the guide is still working', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.resposta
      .mockResolvedValueOnce({ data: { status: 'pending' } })
      .mockResolvedValueOnce({
        data: { status: 'done', available: true, text: 'Você tem 48.' },
      });
    wrapper = mountGuide();

    await perguntar(wrapper, 'quantas conversas abertas eu tenho?');
    await esperarUmaBusca();
    await flushPromises();
    await esperarUmaBusca();
    await flushPromises();

    expect(AutonomiaGuideAPI.resposta).toHaveBeenCalledTimes(2);
    expect(AutonomiaGuideAPI.resposta).toHaveBeenCalledWith('pedido-1');
    // Pelo store: o texto da resposta é renderizado por `v-dompurify-html`, que
    // o teste substitui por uma diretiva vazia.
    expect(useAutonomiaGuideStore().messages[1].message.content).toBe(
      'Você tem 48.'
    );
  });

  // Painel fora da tela não quer mais a resposta. Sem isto a tela seguia
  // consultando o servidor por até três minutos, à toa (achado da revisão).
  it('stops asking once the panel is gone', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'pending' },
    });
    wrapper = mountGuide();

    await perguntar(wrapper, 'me fala sobre minhas conversas');
    await esperarUmaBusca();
    await flushPromises();
    const antes = AutonomiaGuideAPI.resposta.mock.calls.length;

    wrapper.unmount();
    wrapper = null;
    await esperarUmaBusca();
    await flushPromises();
    await esperarUmaBusca();
    await flushPromises();

    expect(antes).toBe(1);
    expect(AutonomiaGuideAPI.resposta).toHaveBeenCalledTimes(1);
  });

  it('ignores a response that settles after starting a new conversation', async () => {
    pedidoAberto();
    let resolveResposta;
    AutonomiaGuideAPI.resposta.mockReturnValue(
      new Promise(resolve => {
        resolveResposta = resolve;
      })
    );
    wrapper = mountGuide();

    await perguntar(wrapper, 'resposta antiga');
    await esperarUmaBusca();
    await flushPromises();
    expect(AutonomiaGuideAPI.resposta).toHaveBeenCalledOnce();

    await wrapper
      .get('button[aria-label="AUTONOMIA_GUIDE.A11Y.NEW_CONVERSATION"]')
      .trigger('click');
    resolveResposta({
      data: { status: 'done', available: true, text: 'Resposta antiga.' },
    });
    await flushPromises();

    expect(useAutonomiaGuideStore().messages).toHaveLength(0);
  });

  // Antes a falha era um aviso que sumia em segundos: quem voltava a olhar
  // via a pergunta sem resposta nenhuma. Agora ela fica escrita na conversa.
  it('writes the failure into the thread when the guide fails', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'failed' },
    });
    wrapper = mountGuide();

    await perguntar(wrapper, 'me fala sobre minhas conversas');
    await esperarUmaBusca();
    await flushPromises();

    const { messages } = useAutonomiaGuideStore();
    expect(messages).toHaveLength(2);
    expect(messages[1].message.content).toBe('AUTONOMIA_GUIDE.ERROR');
  });

  it('writes the failure into the thread when the question never gets through', async () => {
    AutonomiaGuideAPI.chat.mockRejectedValue(new Error('rede'));
    wrapper = mountGuide();

    await perguntar(wrapper, 'oi');
    await flushPromises();

    expect(useAutonomiaGuideStore().messages[1].message.content).toBe(
      'AUTONOMIA_GUIDE.ERROR'
    );
  });

  it('keeps the text and warns when a reply is still loading', async () => {
    AutonomiaGuideAPI.chat.mockReturnValue(new Promise(() => {}));
    wrapper = mountGuide();
    const textarea = wrapper.find('textarea');

    await textarea.setValue('Primeira');
    await textarea.trigger('keydown', { key: 'Enter' });
    await flushPromises();
    await textarea.setValue('Segunda');
    await textarea.trigger('keydown', { key: 'Enter' });
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledOnce();
    expect(textarea.element.value).toBe('Segunda');
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.SENDING');
  });

  it('sends a single request when confirm is clicked twice', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockReturnValue(new Promise(() => {}));
    wrapper = mountGuide();
    await flushPromises();

    const confirmar = findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM');
    await confirmar.trigger('click');
    await confirmar.trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.executarAcao).toHaveBeenCalledOnce();
  });

  it('warns instead of losing the outcome when the record is gone', async () => {
    const store = comAcaoProposta();
    let resolverAcao;
    AutonomiaGuideAPI.executarAcao.mockReturnValue(
      new Promise(resolve => {
        resolverAcao = resolve;
      })
    );
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    // "Nova conversa" durante a execução: o cartão que mostraria o desfecho
    // deixa de existir, mas a ação já rodou no servidor.
    store.reset();
    resolverAcao({ data: { mensagem: 'Pronto, feito.' } });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.ACTION.LOST');
  });

  it('hides a platform error that carries an HTTP status', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockRejectedValue({
      response: { data: { error: 'A plataforma respondeu 422.' } },
    });
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.ACTION.FAILED_GENERIC');
    expect(wrapper.text()).not.toContain('422');
  });

  it('keeps a readable platform error', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockRejectedValue({
      response: { data: { error: 'Este funil não existe mais.' } },
    });
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(wrapper.text()).toContain('Este funil não existe mais.');
  });

  // Revisão da #861: a ação já foi feita em outra aba. O servidor recusa e
  // devolve o resultado guardado; o cartão mostra feita, sem botões.
  it('marks the action as done when the server says it was already done', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockRejectedValue({
      response: {
        status: 409,
        data: {
          error: 'Isto já foi feito.',
          acao_estado: 'feita',
          mensagem: 'Pronto, feito.',
        },
      },
    });
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(useAutonomiaGuideStore().messages[0]).toMatchObject({
      acaoEstado: 'feita',
      acaoResultado: 'Pronto, feito.',
    });
    expect(findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM')).toBeFalsy();
  });

  // Revisão da #861: a conversa aberta foi apagada (em outra aba ou pelo próprio
  // Guia). A pergunta abre uma conversa nova em vez de falhar.
  it('starts a new conversation when the open one no longer exists', async () => {
    const store = useAutonomiaGuideStore();
    store.definirConversa(12);
    AutonomiaGuideAPI.chat
      .mockRejectedValueOnce({ response: { status: 404 } })
      .mockResolvedValueOnce({
        data: { id: 'pedido-2', status: 'pending', conversa_id: 13 },
      });
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'done', available: true, text: 'Assim.' },
    });
    wrapper = mountGuide();
    await flushPromises();

    await perguntar(wrapper, 'Como crio um funil?');
    await esperarUmaBusca();
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledTimes(2);
    expect(AutonomiaGuideAPI.chat.mock.calls[0][0].conversaId).toBe(12);
    expect(AutonomiaGuideAPI.chat.mock.calls[1][0].conversaId).toBeNull();
    expect(store.conversaAtual()).toBe(13);
    expect(useAlert).not.toHaveBeenCalled();
  });

  // Sem conversa na tela, um 404 é o Guia fora do ar para a conta: não repete.
  it('does not retry a 404 when no conversation was open', async () => {
    AutonomiaGuideAPI.chat.mockRejectedValue({ response: { status: 404 } });
    wrapper = mountGuide();
    await flushPromises();

    await perguntar(wrapper, 'Como crio um funil?');

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledOnce();
  });

  it('lets the user confirm again after declining', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockReturnValue(new Promise(() => {}));
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CANCEL').trigger(
      'click'
    );
    await flushPromises();
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.ACTION.CANCELLED');

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaGuideAPI.executarAcao).toHaveBeenCalledOnce();
  });

  // #617 — o artigo que a Central de Ajuda leu ganha um segundo botão,
  // separado do "Ir para a tela": ele abre o artigo inteiro, não navega.
  it('shows a button to read the full article when the guide read one', async () => {
    comArtigoLido();
    wrapper = mountGuide();
    await flushPromises();

    expect(findByLabel(wrapper, 'AUTONOMIA_GUIDE.READ_ARTICLE')).toBeTruthy();
  });

  it('does not show the article button when the guide read no article', async () => {
    const store = useAutonomiaGuideStore();
    store.addAssistantMessage({ content: 'Oi, tudo bem?' });
    wrapper = mountGuide();
    await flushPromises();

    expect(findByLabel(wrapper, 'AUTONOMIA_GUIDE.READ_ARTICLE')).toBeFalsy();
  });

  it('navigates to the full article, scoped to the account, on click', async () => {
    comArtigoLido();
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.READ_ARTICLE').trigger('click');

    expect(routerPush).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { accountId: 1, ref: '02-04' },
    });
  });

  // A pergunta "como eu faço X" pode trazer artigo junto com a resposta; a
  // tela precisa guardar isso no registro, do mesmo jeito que já guarda
  // `navigation` e `acao`. Aqui o backend só manda o campo SINGULAR antigo
  // (sem `artigos`) — o caso de uma instância do deploy blue/green que ainda
  // não subiu a mudança da #636 — e a tela não pode perder o artigo por isso.
  it('carries the article the guide read into the thread, even from the old singular field', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: {
        status: 'done',
        available: true,
        text: 'É em Configurações > Canais.',
        artigo: ARTIGO,
      },
    });
    wrapper = mountGuide();

    await perguntar(wrapper, 'como conecto o whatsapp?');
    await esperarUmaBusca();
    await flushPromises();

    expect(useAutonomiaGuideStore().messages[1].artigos).toEqual([ARTIGO]);
  });

  // #636 — pergunta com várias partes ganha um botão "Ir para" por tela e um
  // link "Ler" por artigo, em duas seções separadas. Rotas reais do registro
  // do Guia, sem parâmetro, para não depender de `useLevarAteLa` resolver id.
  const TELA_A = {
    route_name: 'labels_list',
    params: {},
    highlight: null,
    rotulo: 'Etiquetas',
  };
  const TELA_B = {
    route_name: 'settings_inbox_new',
    params: {},
    highlight: null,
    rotulo: 'Nova caixa',
  };
  const TELA_C = {
    route_name: 'first_steps',
    params: {},
    highlight: null,
    rotulo: 'Primeiros passos',
  };
  const ARTIGO_B = { ref: '02-05', titulo: 'Conectar o Instagram' };
  // O modelo não mandou `rotulo` nesta: o botão cai no numerado, não no genérico repetido.
  const TELA_SEM_ROTULO = {
    route_name: 'settings_inbox_new',
    params: {},
    highlight: null,
    rotulo: null,
  };

  it('shows one "Ir para" button per screen and one "Ler" link per article, with more than one of each', async () => {
    const store = useAutonomiaGuideStore();
    store.addAssistantMessage({
      content: 'Aqui estão os passos.',
      navigations: [TELA_A, TELA_B, TELA_C],
      artigos: [ARTIGO, ARTIGO_B],
    });
    wrapper = mountGuide();
    await flushPromises();

    // Revisão #637 do PR: sem título de seção para os botões de tela — o texto de
    // cada botão já diz "Ir para", repetir isso acima deles seria redundante.
    expect(wrapper.text()).not.toContain('AUTONOMIA_GUIDE.GO_TO_SECTION');
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.READ_SECTION');
    const irPara = wrapper
      .findAll('button')
      .filter(b => b.text().includes('AUTONOMIA_GUIDE.GO_TO_SCREEN_NAMED'));
    const ler = wrapper
      .findAll('button')
      .filter(b => b.text().includes('AUTONOMIA_GUIDE.READ_ARTICLE_NAMED'));

    expect(irPara).toHaveLength(3);
    expect(ler).toHaveLength(2);
  });

  it('looks just like before with a single screen and a single article', async () => {
    const store = useAutonomiaGuideStore();
    store.addAssistantMessage({
      content: 'Aqui está.',
      navigations: [TELA_A],
      artigos: [ARTIGO],
    });
    wrapper = mountGuide();
    await flushPromises();

    expect(wrapper.text()).not.toContain('AUTONOMIA_GUIDE.READ_SECTION');
    expect(findByLabel(wrapper, 'AUTONOMIA_GUIDE.GO_TO_SCREEN')).toBeTruthy();
    expect(findByLabel(wrapper, 'AUTONOMIA_GUIDE.READ_ARTICLE')).toBeTruthy();
  });

  // Backend antigo (deploy blue/green, #636): manda só o campo singular
  // `navigation`, sem `navigations`. O store embrulha, e o botão tem que
  // aparecer do mesmo jeito.
  it('turns an old-shape response with only the singular `navigation` field into a button', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: {
        status: 'done',
        available: true,
        text: 'É em Configurações > Etiquetas.',
        navigation: TELA_A,
      },
    });
    wrapper = mountGuide();

    await perguntar(wrapper, 'onde ficam as etiquetas?');
    await esperarUmaBusca();
    await flushPromises();

    expect(findByLabel(wrapper, 'AUTONOMIA_GUIDE.GO_TO_SCREEN')).toBeTruthy();
  });

  // Revisão #637 do PR: o rótulo chega no botão de verdade, interpolado — não
  // só a chave de tradução. Sem rótulo (TELA_B), o botão fica numerado pela
  // posição entre as telas VÁLIDAS, não pela posição na lista original.
  it('shows the screen label on the "Ir para" button, interpolated, and numbers the ones without a label', async () => {
    const store = useAutonomiaGuideStore();
    store.addAssistantMessage({
      content: 'Aqui.',
      navigations: [TELA_A, TELA_SEM_ROTULO],
    });
    wrapper = mountGuide({ t: tComInterpolacao });
    await flushPromises();

    expect(findByLabel(wrapper, 'Ir para: Etiquetas')).toBeTruthy();
    expect(findByLabel(wrapper, 'Ir para a tela 2')).toBeTruthy();
  });

  // Exercita o filtro de `telasValidas`: uma rota que o roteador recusa (fora
  // do registro do Guia) não vira botão nem quebra as outras.
  it('drops a screen the router refuses to resolve, keeping the valid ones', async () => {
    const recusada = {
      route_name: 'rota_que_nao_existe_no_guia',
      params: {},
      highlight: null,
      rotulo: 'Fantasma',
    };
    const store = useAutonomiaGuideStore();
    store.addAssistantMessage({
      content: 'Aqui.',
      navigations: [TELA_A, recusada],
    });
    wrapper = mountGuide();
    await flushPromises();

    expect(findByLabel(wrapper, 'AUTONOMIA_GUIDE.GO_TO_SCREEN')).toBeTruthy();
    expect(wrapper.text()).not.toContain('Fantasma');
  });

  it('navigates to the screen behind the clicked "Ir para" button', async () => {
    const store = useAutonomiaGuideStore();
    store.addAssistantMessage({
      content: 'Aqui.',
      navigations: [TELA_A, TELA_B],
    });
    wrapper = mountGuide();
    await flushPromises();

    const botoes = wrapper
      .findAll('button')
      .filter(b => b.text().includes('AUTONOMIA_GUIDE.GO_TO_SCREEN_NAMED'));
    await botoes[1].trigger('click');

    expect(routerPush).toHaveBeenCalledWith({
      name: 'settings_inbox_new',
      params: {},
    });
  });

  it('names the panel and the message region for screen readers', async () => {
    wrapper = mountGuide();
    await flushPromises();

    expect(
      wrapper.find('[role="complementary"]').attributes('aria-label')
    ).toBe('AUTONOMIA_GUIDE.A11Y.PANEL');
    const log = wrapper.find('[role="log"]');
    expect(log.attributes('aria-live')).toBe('polite');
    expect(log.attributes('aria-label')).toBe('AUTONOMIA_GUIDE.A11Y.LOG');
    expect(
      wrapper.find('[aria-label="AUTONOMIA_GUIDE.A11Y.SEND"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[aria-label="AUTONOMIA_GUIDE.A11Y.CLOSE"]').exists()
    ).toBe(true);
  });
});

describe('motivoUtilizavel', () => {
  it('returns the reason when it reads as a message to a person', () => {
    expect(motivoUtilizavel('  Este funil não existe mais. ')).toBe(
      'Este funil não existe mais.'
    );
  });

  it('drops a reason that carries an HTTP status code', () => {
    expect(motivoUtilizavel('A plataforma respondeu 422.')).toBe('');
    expect(motivoUtilizavel('500 Internal Server Error')).toBe('');
  });

  it('keeps a number that is not an HTTP status', () => {
    expect(motivoUtilizavel('O limite é de 50 por dia.')).toBe(
      'O limite é de 50 por dia.'
    );
    expect(motivoUtilizavel('O contato 1042 já saiu do funil.')).toBe(
      'O contato 1042 já saiu do funil.'
    );
  });

  it('drops what is not a usable string', () => {
    expect(motivoUtilizavel(undefined)).toBe('');
    expect(motivoUtilizavel('   ')).toBe('');
    expect(motivoUtilizavel('x'.repeat(200))).toBe('');
  });
});

describe('AutonomiaGuideContainer — sugestões da tela aberta (#697)', () => {
  let wrapper;

  const centralCom = artigos =>
    CentralDeAjudaAPI.get.mockResolvedValueOnce({
      data: { capitulos: [{ id: '09', titulo: 'Contatos', artigos }] },
    });
  const textosDasSugestoes = w =>
    w.findAll('[data-sugestao]').map(botao => botao.text());

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaGuideStore().reset();
    vi.clearAllMocks();
    rotaAtual.name = 'home';
  });

  it('mostra os artigos da Central sobre a tela aberta, no máximo 3', async () => {
    rotaAtual.name = 'companies_dashboard_index';
    centralCom([
      {
        ref: '09-09',
        titulo: 'Empresas: cadastro',
        rota: 'companies_dashboard_index',
      },
      { ref: '09-01', titulo: 'Contatos', rota: 'contacts_dashboard_index' },
      {
        ref: '09-10',
        titulo: 'Vincular contato',
        rota: 'companies_dashboard_index',
      },
      {
        ref: '09-11',
        titulo: 'Editar empresa',
        rota: 'companies_dashboard_index',
      },
      {
        ref: '09-12',
        titulo: 'Excluir empresa',
        rota: 'companies_dashboard_index',
      },
    ]);
    wrapper = mountGuide();
    await flushPromises();

    expect(textosDasSugestoes(wrapper)).toEqual([
      'Empresas: cadastro',
      'Vincular contato',
      'Editar empresa',
    ]);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.SUGGESTIONS_THIS_SCREEN');
  });

  it('sem artigo da tela, mantém as sugestões gerais', async () => {
    rotaAtual.name = 'home';
    centralCom([
      { ref: '09-01', titulo: 'Contatos', rota: 'contacts_dashboard_index' },
    ]);
    wrapper = mountGuide();
    await flushPromises();

    expect(textosDasSugestoes(wrapper)).toEqual([
      'AUTONOMIA_GUIDE.SUGGESTIONS.KANBAN',
      'AUTONOMIA_GUIDE.SUGGESTIONS.WHATSAPP',
      'AUTONOMIA_GUIDE.SUGGESTIONS.REPORTS',
    ]);
  });

  it('se a Central não responde, mantém as sugestões gerais', async () => {
    rotaAtual.name = 'companies_dashboard_index';
    CentralDeAjudaAPI.get.mockRejectedValueOnce(new Error('rede'));
    wrapper = mountGuide();
    await flushPromises();

    expect(textosDasSugestoes(wrapper)).toHaveLength(3);
    expect(textosDasSugestoes(wrapper)[0]).toBe(
      'AUTONOMIA_GUIDE.SUGGESTIONS.KANBAN'
    );
  });
});

// #895 — voz e anexos no jeito do WhatsApp.
describe('AutonomiaGuideContainer — voz e anexos', () => {
  let wrapper;

  beforeEach(() => {
    vi.useFakeTimers();
    URL.createObjectURL = vi.fn(() => 'blob:local');
    URL.revokeObjectURL = vi.fn();
  });

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaGuideStore().reset();
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  const composer = () => wrapper.findComponent({ name: 'GuideComposer' });
  const audio = new Blob(['ogg'], { type: 'audio/ogg' });

  it('a mensagem de voz entra como áudio, vira texto e só então o Guia é chamado', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.transcrever.mockResolvedValue({
      data: { texto: 'quantos leads eu tenho' },
    });
    wrapper = mountGuide();

    expect(composer().props('onEnviarVoz')({ audio, duracao: 4 })).toBe(true);
    await flushPromises();

    expect(AutonomiaGuideAPI.transcrever).toHaveBeenCalledWith(audio);
    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledWith(
      expect.objectContaining({
        message: 'quantos leads eu tenho',
        history: [{ role: 'user', content: 'quantos leads eu tenho' }],
      })
    );
    const balao = wrapper.findComponent({ name: 'GuideUserMessage' });
    expect(balao.findComponent({ name: 'GuideVoz' }).props('src')).toBe(
      'blob:local'
    );
    expect(balao.text()).toContain('quantos leads eu tenho');
  });

  it('transcrição que falha: erro no balão, nada pedido, e tentar de novo funciona', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.transcrever
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValueOnce({ data: { texto: 'cria a etiqueta urgente' } });
    wrapper = mountGuide();

    composer().props('onEnviarVoz')({ audio, duracao: 2 });
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.VOICE.FAILED');
    expect(composer().props('isBusy')).toBe(false);

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.VOICE.RETRY').trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.transcrever).toHaveBeenCalledTimes(2);
    expect(AutonomiaGuideAPI.transcrever).toHaveBeenLastCalledWith(audio);
    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'cria a etiqueta urgente' })
    );
  });

  it('transcrição vazia conta como falha', async () => {
    AutonomiaGuideAPI.transcrever.mockResolvedValue({ data: { texto: '  ' } });
    wrapper = mountGuide();

    composer().props('onEnviarVoz')({ audio, duracao: 1 });
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.VOICE.FAILED');
  });

  it('só uma foto, sem texto: o balão mostra a foto e o Guia recebe a frase padrão', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.enviarArquivo.mockResolvedValue({
      data: { signed_id: 'foto-1', nome: 'print.png' },
    });
    wrapper = mountGuide();
    const foto = new File(['png'], 'print.png', { type: 'image/png' });

    composer().vm.$emit('anexar', foto);
    await flushPromises();
    expect(composer().props('arquivos')).toHaveLength(1);

    expect(composer().props('onSend')('')).toBe(true);
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledWith(
      expect.objectContaining({
        message: 'AUTONOMIA_GUIDE.FILE.DEFAULT_MESSAGE',
        arquivos: ['foto-1'],
      })
    );
    expect(composer().props('arquivos')).toHaveLength(0);
    const balao = wrapper.findComponent({ name: 'GuideUserMessage' });
    expect(balao.find('img').attributes('src')).toBe('blob:local');
  });

  it('com gravação no campo, nenhuma outra mensagem sai (o áudio não se perde)', async () => {
    wrapper = mountGuide();
    await flushPromises();

    composer().vm.$emit('gravando', true);
    await flushPromises();

    expect(composer().props('onSend')('oi')).toBe(false);
    expect(AutonomiaGuideAPI.chat).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.VOICE.FINISH_FIRST');
    const sugestoes = wrapper.findAll('[data-sugestao]');
    expect(sugestoes.length).toBeGreaterThan(0);
    sugestoes.forEach(sugestao =>
      expect(sugestao.attributes('disabled')).toBeDefined()
    );

    composer().vm.$emit('gravando', false);
    await flushPromises();
    expect(
      wrapper.find('[data-sugestao]').attributes('disabled')
    ).toBeUndefined();
  });

  it('a mensagem de voz sai mesmo com a gravação ainda marcada', async () => {
    pedidoAberto();
    AutonomiaGuideAPI.transcrever.mockResolvedValue({ data: { texto: 'oi' } });
    wrapper = mountGuide();
    composer().vm.$emit('gravando', true);
    await flushPromises();

    expect(composer().props('onEnviarVoz')({ audio, duracao: 1 })).toBe(true);
  });

  it('o sexto anexo da conversa é recusado com aviso', async () => {
    let numero = 0;
    AutonomiaGuideAPI.enviarArquivo.mockImplementation(() => {
      numero += 1;
      return Promise.resolve({
        data: { signed_id: `a-${numero}`, nome: `a${numero}.pdf` },
      });
    });
    wrapper = mountGuide();

    for (let i = 1; i <= 5; i += 1) {
      composer().vm.$emit('anexar', new File(['x'], `a${i}.pdf`));
    }
    await flushPromises();
    expect(composer().props('vagas')).toBe(0);

    composer().vm.$emit('anexar', new File(['x'], 'a6.pdf'));
    await flushPromises();

    expect(AutonomiaGuideAPI.enviarArquivo).toHaveBeenCalledTimes(5);
    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.FILE.LIMIT');
  });

  it('anexo que falhou ao subir não ocupa vaga', async () => {
    AutonomiaGuideAPI.enviarArquivo.mockRejectedValue(new Error('tipo'));
    wrapper = mountGuide();

    composer().vm.$emit('anexar', new File(['x'], 'a.exe'));
    await flushPromises();

    expect(composer().props('vagas')).toBe(5);
  });

  it('o composer avisa o limite e a tela mostra a mensagem', async () => {
    wrapper = mountGuide();

    composer().vm.$emit('limiteDeAnexos');

    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.FILE.LIMIT');
  });

  it('não envia enquanto um anexo ainda está subindo', async () => {
    AutonomiaGuideAPI.enviarArquivo.mockReturnValue(new Promise(() => {}));
    wrapper = mountGuide();

    composer().vm.$emit('anexar', new File(['x'], 'a.pdf'));
    await flushPromises();

    expect(composer().props('onSend')('lê isso')).toBe(false);
    expect(AutonomiaGuideAPI.chat).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.FILE.WAIT');
  });
});

// #861 — a conversa fica guardada: abrir o painel reabre a atual, e a pergunta
// seguinte continua a mesma conversa no servidor.
describe('AutonomiaGuideContainer — conversa guardada', () => {
  let wrapper;

  const turno = (extra = {}) => ({
    pedido_id: 'p1',
    pergunta: 'quantos funis?',
    anexos: [],
    status: 'done',
    resposta: 'São 3.',
    navegacoes: [],
    artigos: [],
    acao: null,
    acao_estado: null,
    acao_resultado: null,
    execucao: null,
    ...extra,
  });

  const conversaGuardada = turnos =>
    AutonomiaGuideAPI.conversaAtual.mockResolvedValueOnce({
      data: { id: 7, titulo: 'funis', turnos },
    });

  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaGuideStore().reset();
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it('reabre a conversa atual ao abrir o painel', async () => {
    conversaGuardada([turno()]);
    wrapper = mountGuide();
    await flushPromises();

    expect(AutonomiaGuideAPI.conversaAtual).toHaveBeenCalledOnce();
    expect(
      useAutonomiaGuideStore().messages.map(m => m.message.content)
    ).toEqual(['quantos funis?', 'São 3.']);
  });

  it('continua a mesma conversa na pergunta seguinte', async () => {
    conversaGuardada([turno()]);
    pedidoAberto();
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: {
        status: 'done',
        available: true,
        text: 'Vendas, Pós e Renovação.',
      },
    });
    wrapper = mountGuide();
    await flushPromises();

    await perguntar(wrapper, 'e quais são?');

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledWith(
      expect.objectContaining({ conversaId: 7, message: 'e quais são?' })
    );
  });

  it('guarda a conversa que o servidor abriu na primeira pergunta', async () => {
    AutonomiaGuideAPI.chat.mockResolvedValue({
      data: { id: 'pedido-1', status: 'pending', conversa_id: 12 },
    });
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'done', available: true, text: 'Oi!' },
    });
    wrapper = mountGuide();
    await flushPromises();

    await perguntar(wrapper, 'oi');
    await esperarUmaBusca();
    await flushPromises();

    expect(useAutonomiaGuideStore().conversaAtual()).toBe(12);
    expect(useAutonomiaGuideStore().messages[1].pedidoId).toBe('pedido-1');
  });

  it('volta a buscar a resposta de uma pergunta que ficou pendente', async () => {
    conversaGuardada([
      turno({ pedido_id: 'p9', status: 'pending', resposta: null }),
    ]);
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'done', available: true, text: 'Chegou.' },
    });
    wrapper = mountGuide();
    await flushPromises();
    await esperarUmaBusca();
    await flushPromises();

    expect(AutonomiaGuideAPI.resposta).toHaveBeenCalledWith('p9');
    expect(useAutonomiaGuideStore().messages[1].message.content).toBe(
      'Chegou.'
    );
  });

  it('a ação que esperava confirmação volta com os botões, e confirmar guarda o desfecho', async () => {
    conversaGuardada([turno({ acao: ACAO })]);
    AutonomiaGuideAPI.executarAcao.mockResolvedValue({
      data: { mensagem: 'Pronto.' },
    });
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaGuideAPI.executarAcao).toHaveBeenCalledWith(
      expect.objectContaining({ acao: ACAO.nome, pedidoId: 'p1' })
    );
  });

  it('se a conversa não abre, diz isso e deixa começar outra', async () => {
    AutonomiaGuideAPI.conversaAtual.mockRejectedValueOnce(new Error('rede'));
    wrapper = mountGuide();
    await flushPromises();

    expect(wrapper.find('[data-falhou-ao-abrir]').exists()).toBe(true);
    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.HISTORY.START_NEW').trigger(
      'click'
    );

    expect(wrapper.find('[data-falhou-ao-abrir]').exists()).toBe(false);
    expect(wrapper.find('[data-sugestao]').exists()).toBe(true);
  });

  it('mostra o esqueleto só quando abrir demora', async () => {
    let abrir;
    AutonomiaGuideAPI.conversaAtual.mockReturnValueOnce(
      new Promise(resolve => {
        abrir = resolve;
      })
    );
    wrapper = mountGuide();
    await flushPromises();
    expect(wrapper.find('[data-esqueleto]').exists()).toBe(false);
    expect(wrapper.find('[data-sugestao]').exists()).toBe(false);

    await vi.advanceTimersByTimeAsync(300);
    expect(wrapper.find('[data-esqueleto]').exists()).toBe(true);

    abrir({ data: { id: 7, turnos: [turno()] } });
    await flushPromises();
    expect(wrapper.find('[data-esqueleto]').exists()).toBe(false);
  });

  it('"Nova conversa" começa outra sem apagar a guardada', async () => {
    conversaGuardada([turno()]);
    wrapper = mountGuide();
    await flushPromises();

    wrapper.findComponent({ name: 'GuideHeader' }).vm.$emit('reset');
    await flushPromises();

    expect(useAutonomiaGuideStore().conversaAtual()).toBeNull();
    expect(useAutonomiaGuideStore().messages).toHaveLength(0);
    expect(AutonomiaGuideAPI.apagarConversa).not.toHaveBeenCalled();
  });
});

// #859 — a mesma conversa embutida na tela de Automações.
describe('AutonomiaGuideContainer — embutido', () => {
  let wrapper;

  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaGuideStore().reset();
    vi.clearAllMocks();
    vi.useRealTimers();
    rotaAtual.name = 'home';
    delete rotaAtual.params;
    delete rotaAtual.meta;
  });

  const montarEmbutido = props =>
    mount(AutonomiaGuideContainer, {
      attachTo: document.body,
      props: { embutido: true, ...props },
      global: {
        mocks: { $t: key => key },
        directives: { onClickOutside: {}, dompurifyHtml: {} },
      },
    });

  it('o painel lateral não abre por cima da tela que já traz a conversa', async () => {
    rotaAtual.meta = { guiaEmbutido: true };
    wrapper = mountGuide();
    await flushPromises();

    expect(wrapper.find('[role="complementary"]').exists()).toBe(false);
  });

  // Decisão da integração do lote 10: a página de Automações começa limpa — não
  // traz de volta a conversa guardada do painel lateral.
  it('embutido começa limpo: não reabre a conversa guardada', async () => {
    rotaAtual.meta = { guiaEmbutido: true };
    AutonomiaGuideAPI.conversaAtual.mockResolvedValueOnce({
      data: {
        id: 7,
        titulo: 'funis',
        turnos: [{ id: 1, pergunta: 'quantos funis?', resposta: 'São 3.' }],
      },
    });
    wrapper = montarEmbutido();
    await flushPromises();

    expect(AutonomiaGuideAPI.conversaAtual).not.toHaveBeenCalled();
    expect(useAutonomiaGuideStore().messages).toHaveLength(0);
  });

  it('embutido: sem cabeçalho, com as sugestões e a introdução da tela', async () => {
    rotaAtual.meta = { guiaEmbutido: true };
    wrapper = montarEmbutido({
      sugestoes: [{ rotulo: 'Agradecer', pergunta: 'Quero agradecer' }],
      introducao: 'Conte o que automatizar.',
    });
    await flushPromises();

    expect(wrapper.find('[role="region"]').exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'GuideHeader' }).exists()).toBe(false);
    expect(wrapper.text()).toContain('Conte o que automatizar.');
    expect(wrapper.find('[data-sugestao]').text()).toBe('Agradecer');
  });

  it('manda o registro aberto, avisa a tela do que o Guia fez e não apaga a conversa ao sair', async () => {
    rotaAtual.name = 'automacoes_editar';
    rotaAtual.params = { accountId: '1', id: '42' };
    pedidoAberto();
    const execucao = {
      id: 9,
      passos: [{ acao: 'PATCH automation_rules/:id', ok: true, registro: 42 }],
    };
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'done', available: true, text: 'Liguei.', execucao },
    });
    wrapper = montarEmbutido();

    await perguntar(wrapper, 'liga esta');
    await esperarUmaBusca();
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledWith(
      expect.objectContaining({
        routeContext: 'automacoes_editar',
        routeParams: { accountId: '1', id: '42' },
      })
    );
    expect(wrapper.emitted('execucao')).toEqual([[execucao]]);

    wrapper.unmount();
    wrapper = null;
    expect(useAutonomiaGuideStore().messages).toHaveLength(2);
  });

  it('o modelo escolhido na lista vira a primeira pergunta, uma vez só', async () => {
    pedidoAberto();
    wrapper = montarEmbutido({ pedidoInicial: 'Quero agradecer' });
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledOnce();
    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Quero agradecer' })
    );
  });
  it('avisa a tela quando o pedido inicial sai', async () => {
    pedidoAberto();
    wrapper = montarEmbutido({ pedidoInicial: 'Quero agradecer' });
    await flushPromises();

    expect(wrapper.emitted('pedidoInicialEnviado')).toHaveLength(1);
  });

  // Revisão #859: a conversa embutida sai junto com a tela. Antes, a busca
  // parava e a resposta (e o que o Guia fez) nunca entrava na conversa.
  it('sair da tela no meio da resposta: o painel lateral termina de buscar', async () => {
    rotaAtual.meta = { guiaEmbutido: true };
    pedidoAberto();
    AutonomiaGuideAPI.resposta
      .mockResolvedValueOnce({ data: { status: 'pending' } })
      .mockResolvedValue({
        data: { status: 'done', available: true, text: 'Criei a automação.' },
      });
    const painel = mountGuide();
    wrapper = montarEmbutido();

    await perguntar(wrapper, 'cria uma automação que etiqueta sinistro');
    await esperarUmaBusca();
    await flushPromises();
    wrapper.unmount();
    wrapper = null;
    await esperarUmaBusca();
    await flushPromises();

    const { messages } = useAutonomiaGuideStore();
    expect(messages).toHaveLength(2);
    expect(messages[1].message.content).toBe('Criei a automação.');
    expect(AutonomiaGuideAPI.resposta).toHaveBeenCalledWith('pedido-1');
    expect(useAutonomiaGuideStore().temPendente()).toBe(false);
    painel.unmount();
  });

  it('sair antes de o servidor aceitar a pergunta: o painel adota quando ela é aceita', async () => {
    rotaAtual.meta = { guiaEmbutido: true };
    let aceitar;
    AutonomiaGuideAPI.chat.mockReturnValue(
      new Promise(resolve => {
        aceitar = resolve;
      })
    );
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'done', available: true, text: 'Pronto.' },
    });
    const painel = mountGuide();
    wrapper = montarEmbutido();

    await perguntar(wrapper, 'cria uma automação');
    wrapper.unmount();
    wrapper = null;
    aceitar({ data: { id: 'pedido-2', status: 'pending' } });
    await flushPromises();
    await esperarUmaBusca();
    await flushPromises();

    expect(AutonomiaGuideAPI.resposta).toHaveBeenCalledWith('pedido-2');
    expect(useAutonomiaGuideStore().messages[1].message.content).toBe(
      'Pronto.'
    );
    painel.unmount();
  });

  it('enquanto outra parte da tela espera a resposta, nenhuma pergunta nova sai', async () => {
    rotaAtual.meta = { guiaEmbutido: true };
    pedidoAberto();
    AutonomiaGuideAPI.resposta.mockResolvedValue({
      data: { status: 'pending' },
    });
    const painel = mountGuide();
    wrapper = montarEmbutido();
    await perguntar(wrapper, 'primeira');
    wrapper.unmount();
    wrapper = montarEmbutido();
    await flushPromises();

    await perguntar(wrapper, 'segunda');

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledOnce();
    expect(
      wrapper.findComponent({ name: 'GuideComposer' }).props('isBusy')
    ).toBe(true);
    painel.unmount();
  });
});
