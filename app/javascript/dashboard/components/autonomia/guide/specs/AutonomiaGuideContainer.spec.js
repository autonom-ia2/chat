import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import {
  useAutonomiaGuideStore,
  motivoUtilizavel,
} from 'dashboard/store/modules/autonomiaGuide';
import AutonomiaGuideContainer from '../AutonomiaGuideContainer.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
// Espião estável: `useRouter()` roda de novo a cada teste, e um `vi.fn()`
// novo a cada chamada não deixaria como afirmar QUAL rota o clique pediu.
const { routerPush } = vi.hoisted(() => ({ routerPush: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home' }),
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
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: true }));
    }
    if (getter === 'getCurrentAccountId') return ref(1);
    // `accounts/isFeatureEnabledonAccount`: as telas usadas nestes testes exigem recurso ligado
    // na conta (#636 usa rotas reais do registro, e a maioria tem `gate` de feature).
    return ref(() => true);
  },
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { chat: vi.fn(), resposta: vi.fn(), executarAcao: vi.fn() },
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
