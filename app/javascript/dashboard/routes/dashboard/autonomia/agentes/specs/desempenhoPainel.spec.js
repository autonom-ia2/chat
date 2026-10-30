import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import EstadoDoPainel from '../components/desempenho/EstadoDoPainel.vue';
import AgenteSemana from '../components/pagina/AgenteSemana.vue';
import DeltaDoNumero from '../components/desempenho/comum/DeltaDoNumero.vue';
import RankingDeBarras from '../components/desempenho/comum/RankingDeBarras.vue';
import MapaDeCalor from '../components/desempenho/resumo/MapaDeCalor.vue';
import SecaoFunil from '../components/desempenho/resumo/SecaoFunil.vue';
import demo from '../utils/desempenhoDemo.json';
import DesempenhoPage from '../pages/DesempenhoPage.vue';
import { VARIANTES } from '../utils/desempenhoEstados';

// #2226 v2 — o painel de desempenho em tela, com a demonstração inventada (desempenhoDemo.json, uma
// loja genérica): os 8 números, a aba e o período no endereço, o mapa de calor sempre visível com o
// número na célula, a origem com e sem anúncio, a ressalva da qualidade otimista, os botões de
// exportar desligados sem arquivo e nenhum <select> nativo. Também as peças comuns (delta, ranking),
// cada variante do EstadoDoPainel e o link "Ver tudo de {nome}".
const rota = vi.hoisted(() => ({ atual: null }));
const router = vi.hoisted(() => ({
  replace: vi.fn(),
  push: vi.fn(),
  resolve: vi.fn(destino => ({
    href: `/app/${destino.name}/${destino.params?.conversation_id ?? ''}`,
  })),
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota.atual,
  useRouter: () => router,
}));
const estado = vi.hoisted(() => ({
  admin: true,
  gerencia: true,
  exporta: true,
}));
const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  getters: { 'autonomiaAgents/getRecord': () => null },
  state: {},
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state[nome]),
  };
});
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => estado.admin) }) };
});
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => estado.gerencia),
    usePermissionGranted: chave =>
      computed(() => chave !== 'contact_export' || estado.exporta),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomia/agents', () => ({
  default: { show: vi.fn().mockRejectedValue(new Error('demo')) },
}));
// #2251: a página lê da API. Aqui a API devolve a própria demonstração do período (os testes da tela
// continuam sobre ela); `respostaDaApi` troca a resposta nos testes da API.
const respostaDaApi = vi.hoisted(() => ({ painel: null, arquivo: null }));
vi.mock('dashboard/api/autonomia/desempenho', async () => {
  const { painelDemo } = await import('../utils/desempenhoFonte');
  return {
    default: {
      painel: vi.fn(async ({ periodo }) => ({
        data: respostaDaApi.painel || (await painelDemo({ periodo })),
      })),
      exportar: vi.fn(async () => ({ data: respostaDaApi.arquivo })),
    },
  };
});

const KPIS = [
  'procuras',
  'conversas',
  'compra',
  'fecharam',
  'duvidas_resolvidas',
  'sem_pessoa',
  'perdas_evitaveis',
  'tempo_resposta',
];

describe('DesempenhoPage', () => {
  const abrir = async (query = {}) => {
    rota.atual = reactive({ query, params: { agentId: '5' } });
    const wrapper = mount(DesempenhoPage, {
      props: { agentId: '5' },
      attachTo: document.body,
      global: {
        stubs: { AbaDetalhe: { template: '<div data-aba-detalhe />' } },
      },
    });
    // A demonstração é importada sob demanda e a exportação pergunta pelo arquivo: espera os dois.
    await vi.waitFor(() => {
      expect(wrapper.find('[data-faixa]').exists()).toBe(true);
      expect(wrapper.find('[data-exportar][aria-busy]').exists()).toBe(false);
    });
    return wrapper;
  };

  beforeEach(() => {
    estado.admin = true;
    estado.gerencia = true;
    estado.exporta = true;
    respostaDaApi.painel = null;
    respostaDaApi.arquivo = null;
    // Nenhum arquivo local (vida real nem exportação): a página cai na demonstração.
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false }));
    router.replace.mockImplementation(({ query }) => {
      rota.atual.query = query;
    });
    router.resolve.mockImplementation(destino => ({
      href: `/app/${destino.name}/${destino.params?.conversation_id ?? ''}`,
    }));
    store.state = {
      'accounts/getAccount': () => ({}),
      getCurrentAccountId: 1,
      'agentBots/getBots': [],
    };
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    document.body.innerHTML = '';
  });

  it('shows the 8 numbers in order, each with its explanation', async () => {
    const wrapper = await abrir();
    const kpis = wrapper.findAll('[data-kpi]');
    expect(kpis.map(kpi => kpi.attributes('data-id'))).toEqual(KPIS);
    kpis.forEach(kpi => {
      expect(kpi.get('[data-numero]').text()).not.toBe('');
      expect(kpi.get('[data-explica]').text()).not.toBe('');
    });
    // "Compra" e "fechou" têm o nome do negócio, que vem dos dados.
    expect(wrapper.get('[data-kpi][data-id="compra"] h3').text()).toBe(
      'Pedidos de compra'
    );
    expect(wrapper.get('[data-kpi][data-id="fecharam"] h3').text()).toBe(
      'Fecharam'
    );
    expect(
      wrapper
        .findAll('[data-leitura]')
        .map(item => item.attributes('data-leitura'))
    ).toEqual(['VOLUME', 'RITMO', 'TRAVA', 'DECISAO']);
  });

  it('explains next to the funnel why its last step and the result differ, only when they do', () => {
    const comNota = mount(SecaoFunil, {
      props: {
        painel: {
          ...demo,
          funil: {
            ...demo.funil,
            conciliacao: {
              chegaram_ao_fim: 13,
              chegaram_e_nao_fecharam: 1,
              fecharam_sem_chegar: 5,
              fecharam: 17,
            },
          },
        },
      },
    });
    expect(comNota.find('[data-conciliacao]').exists()).toBe(true);
    // Na demonstração os dois números batem: não há o que explicar.
    const semNota = mount(SecaoFunil, { props: { painel: demo } });
    expect(semNota.find('[data-conciliacao]').exists()).toBe(false);
  });

  it('shows each comparison on its own line and "few cases" only once', async () => {
    const wrapper = await abrir();
    const linhas = wrapper.findAll('#funil [data-comparacao]');
    expect(linhas.length).toBeGreaterThan(0);
    linhas.forEach(linha =>
      expect(linha.findAll('[data-poucos-casos]').length).toBeLessThanOrEqual(1)
    );
  });

  it('says the numbers are made up when the source is the demonstration', async () => {
    const wrapper = await abrir();
    expect(wrapper.find('[data-aviso-demo]').exists()).toBe(true);
    expect(wrapper.find('[data-aviso-fonte]').exists()).toBe(false);
  });

  it('keeps "did not act" out of the quality base', async () => {
    const wrapper = await abrir();
    expect(wrapper.get('[data-qualidade="nao_atuou"]').text()).toContain(
      'FORA_DA_BASE'
    );
    expect(wrapper.get('[data-qualidade="acertou"]').text()).toContain('%');
  });

  it('lists the conversations that ask the most, with what to do when none closed', async () => {
    const wrapper = await abrir();
    const linhas = wrapper.findAll('[data-mais-pedem-linha]');
    expect(linhas.length).toBeGreaterThan(0);
    expect(linhas.length).toBeLessThanOrEqual(5);
  });

  it('keeps the tab in the address', async () => {
    const wrapper = await abrir();
    expect(wrapper.find('#numeros').exists()).toBe(true);
    await wrapper.get('[data-abas] [data-opcao="detalhe"]').trigger('click');
    expect(router.replace).toHaveBeenLastCalledWith({
      query: { aba: 'detalhe' },
    });
    await flushPromises();
    expect(wrapper.find('[data-aba-detalhe]').exists()).toBe(true);
    expect(wrapper.find('#numeros').exists()).toBe(false);
  });

  it('keeps the period in the address and reloads the numbers', async () => {
    const wrapper = await abrir();
    const procuras30 = wrapper
      .get('[data-kpi][data-id="procuras"] [data-numero]')
      .text();
    await wrapper.get('[data-periodos] [data-opcao="7"]').trigger('click');
    expect(router.replace).toHaveBeenLastCalledWith({
      query: { periodo: '7' },
    });
    await vi.waitFor(() =>
      expect(
        wrapper.get('[data-kpi][data-id="procuras"] [data-numero]').text()
      ).not.toBe(procuras30)
    );
    expect(
      wrapper.get('[data-periodos] [data-opcao="7"]').attributes('aria-pressed')
    ).toBe('true');
    expect(
      wrapper.get('[data-kpi][data-id="procuras"] [data-numero]').text()
    ).not.toBe(procuras30);
  });

  it('opens straight on the Detail tab from the address', async () => {
    const wrapper = await abrir({ aba: 'detalhe' });
    expect(wrapper.find('[data-aba-detalhe]').exists()).toBe(true);
  });

  it('takes a theme click to the filtered Detail tab', async () => {
    const wrapper = await abrir({ periodo: '30' });
    await wrapper.get('[data-temas] [data-item] button').trigger('click');
    const { query } = router.replace.mock.calls.at(-1)[0];
    expect(query.aba).toBe('detalhe');
    expect(query.periodo).toBe('30');
    expect(query.tema).toBeTruthy();
  });

  it('always shows the heat map with the number inside the cell', async () => {
    const wrapper = await abrir();
    const mapa = wrapper.get('[data-mapa]');
    expect(mapa.findAll('[data-celula]')).toHaveLength(7 * 24);
    const pico = mapa.get('[data-pico]');
    expect(Number(pico.text())).toBeGreaterThan(0);
    expect(pico.attributes('aria-label')).toBeTruthy();
    expect(wrapper.find('[data-total-geral]').text()).not.toBe('');
  });

  it('compares ads and no ads with the same measure when ads are on', async () => {
    const wrapper = await abrir();
    const origem = wrapper.get('#origem');
    expect(origem.attributes('data-estado-origem')).toBe('com_anuncio');
    expect(origem.findAll('[data-lado]')).toHaveLength(2);
    expect(origem.find('[data-por-anuncio]').exists()).toBe(true);
    expect(origem.find('[data-sem-anuncio]').exists()).toBe(false);
  });

  it('says calmly that the account has no ads, with the link only for admins', async () => {
    const wrapper = await abrir({ fonte: 'demo', anuncio: '0' });
    const origem = wrapper.get('#origem');
    expect(origem.attributes('data-estado-origem')).toBe('sem_anuncio');
    expect(origem.find('[data-lado]').exists()).toBe(false);
    expect(origem.find('[data-como-chegaram]').exists()).toBe(true);
    // A taxa por origem já está embaixo de cada barra: não há um 2º cartão repetindo os números.
    expect(origem.find('[data-quem-fecha]').exists()).toBe(false);
    expect(origem.find('[data-ligar-anuncios]').exists()).toBe(true);

    estado.admin = false;
    const semAdmin = await abrir({ fonte: 'demo', anuncio: '0' });
    expect(semAdmin.find('[data-ligar-anuncios]').exists()).toBe(false);
  });

  it('warns next to the quality numbers when the check found them optimistic', async () => {
    const wrapper = await abrir();
    expect(wrapper.find('#qualidade [data-otimista]').exists()).toBe(true);
  });

  it('turns the export buttons off when there is no file yet', async () => {
    const wrapper = await abrir();
    const botoes = wrapper.findAll('[data-exportar]');
    expect(botoes).toHaveLength(2);
    botoes.forEach(botao => expect(botao.attributes('disabled')).toBeDefined());
    expect(wrapper.find('[data-sem-exportacao]').exists()).toBe(true);
  });

  it('turns an export button on when its file exists', async () => {
    globalThis.fetch.mockImplementation((endereco, opcoes) =>
      Promise.resolve({
        ok: opcoes?.method === 'HEAD' && endereco.endsWith('.pdf'),
      })
    );
    const wrapper = await abrir({ fonte: 'demo' });
    expect(
      wrapper.get('[data-exportar="pdf"]').attributes('disabled')
    ).toBeUndefined();
    expect(
      wrapper.get('[data-exportar="xlsx"]').attributes('disabled')
    ).toBeDefined();
  });

  it('shows the empty state and no numbers when the API has no reading for the agent (#2251)', async () => {
    respostaDaApi.painel = {
      versao: 2,
      vazio: true,
      meta: {
        fonte: 'api',
        situacao: 'leitura_desligada',
        periodo: { chave: '30' },
      },
    };
    const wrapper = await abrir();
    expect(wrapper.find('[data-estado="leitura_desligada"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-kpi]').exists()).toBe(false);
    expect(wrapper.find('[data-aviso-demo]').exists()).toBe(false);
    wrapper
      .findAll('[data-exportar]')
      .forEach(botao => expect(botao.attributes('disabled')).toBeDefined());
  });

  it('says how many requests from hidden inboxes are left out of the lists (#2251)', async () => {
    respostaDaApi.painel = {
      ...demo,
      meta: {
        ...demo.meta,
        fonte: 'api',
        visibilidade: { escopo: 'caixas', minimo: 5, ocultas: 3 },
      },
    };
    const wrapper = await abrir();
    expect(wrapper.find('[data-aviso-caixas]').exists()).toBe(true);

    respostaDaApi.painel = { ...demo, meta: { ...demo.meta, fonte: 'api' } };
    const semOcultas = await abrir();
    expect(semOcultas.find('[data-aviso-caixas]').exists()).toBe(false);
  });

  it('says how many conversations the automatic reading could not read (#2301)', async () => {
    respostaDaApi.painel = {
      ...demo,
      meta: { ...demo.meta, fonte: 'api', nao_lidas: 2 },
    };
    const wrapper = await abrir();
    expect(wrapper.find('[data-aviso-nao-lidas]').exists()).toBe(true);

    respostaDaApi.painel = {
      ...demo,
      meta: { ...demo.meta, fonte: 'api', nao_lidas: 0 },
    };
    const semNaoLidas = await abrir();
    expect(semNaoLidas.find('[data-aviso-nao-lidas]').exists()).toBe(false);
  });

  it('says how many conversations wait for the next automatic reading (#2301)', async () => {
    respostaDaApi.painel = {
      ...demo,
      meta: { ...demo.meta, fonte: 'api', pendentes: 3 },
    };
    const wrapper = await abrir();
    expect(wrapper.find('[data-aviso-pendentes]').exists()).toBe(true);

    respostaDaApi.painel = {
      ...demo,
      meta: { ...demo.meta, fonte: 'api', pendentes: 0 },
    };
    const semPendentes = await abrir();
    expect(semPendentes.find('[data-aviso-pendentes]').exists()).toBe(false);
  });

  it('hides the export buttons from whoever lacks contact_export (#2251)', async () => {
    respostaDaApi.painel = { ...demo, meta: { ...demo.meta, fonte: 'api' } };
    estado.exporta = false;
    const wrapper = await abrir();
    expect(wrapper.find('[data-exportar]').exists()).toBe(false);
    expect(wrapper.find('[data-sem-exportacao]').exists()).toBe(false);
    const { default: api } = await import('dashboard/api/autonomia/desempenho');
    expect(api.exportar).not.toHaveBeenCalled();
  });

  it('has no drawer that pretends to save the instruction or the result (#2251)', async () => {
    const wrapper = await abrir({ fonte: 'demo', estado: 'sem_resultado' });
    expect(wrapper.find('[data-colar-instrucao]').exists()).toBe(false);
    expect(wrapper.find('[data-acao-estado]').exists()).toBe(false);
  });

  it('downloads the file from the API with the authenticated request (#2251)', async () => {
    respostaDaApi.painel = { ...demo, meta: { ...demo.meta, fonte: 'api' } };
    respostaDaApi.arquivo = new Blob(['pdf']);
    const criar = vi.fn(() => 'blob:painel');
    vi.stubGlobal('URL', { createObjectURL: criar, revokeObjectURL: vi.fn() });
    const clique = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => {});
    const wrapper = await abrir();
    const botao = wrapper.get('[data-exportar="pdf"]');
    expect(botao.attributes('disabled')).toBeUndefined();
    await botao.trigger('click');
    await flushPromises();
    const { default: api } = await import('dashboard/api/autonomia/desempenho');
    expect(api.exportar).toHaveBeenCalledWith(
      expect.objectContaining({
        agentId: '5',
        origem: 'nosso',
        periodo: '30',
        formato: 'pdf',
      })
    );
    expect(criar).toHaveBeenCalledWith(respostaDaApi.arquivo);
    expect(clique).toHaveBeenCalled();
    // O endereço temporário do arquivo é solto no tique seguinte: espera, antes de devolver o URL real.
    await vi.waitFor(() =>
      expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:painel')
    );
    clique.mockRestore();
  });

  it('has no native select anywhere', async () => {
    const wrapper = await abrir();
    expect(wrapper.find('select').exists()).toBe(false);
    const detalhe = await abrir({
      fonte: 'demo',
      anuncio: '0',
      estado: 'conferencia_baixa',
    });
    expect(detalhe.find('select').exists()).toBe(false);
  });

  it('shows only the empty state when there are no conversations', async () => {
    const wrapper = await abrir({ fonte: 'demo', estado: 'sem_conversas' });
    expect(wrapper.find('[data-estado="sem_conversas"]').exists()).toBe(true);
    expect(wrapper.find('#numeros').exists()).toBe(false);
    expect(wrapper.find('[data-base]').exists()).toBe(false);
  });

  it('links each proof to the conversation, in a new tab', async () => {
    const wrapper = await abrir();
    const link = wrapper.get('#acoes [data-link-conversa] a');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.attributes('href')).toContain('inbox_conversation');
  });
});

describe('DeltaDoNumero', () => {
  const montar = kpi =>
    mount(DeltaDoNumero, {
      props: {
        kpi: { formato: 'numero', melhor: 'subir', ...kpi },
        dias: 30,
      },
    });

  it('is green when the number went the good way', () => {
    const wrapper = montar({ valor: 10, anterior: 7 });
    expect(wrapper.get('[data-delta]').attributes('data-sentido')).toBe(
      'favoravel'
    );
    expect(wrapper.get('[data-delta]').classes()).toContain('text-n-teal-11');
  });

  it('is red when a number that should fall went up', () => {
    const wrapper = montar({ valor: 10, anterior: 7, melhor: 'descer' });
    expect(wrapper.get('[data-delta]').classes()).toContain('text-n-ruby-11');
  });

  it('does not render without the previous period', () => {
    expect(
      montar({ valor: 10, anterior: null }).find('[data-delta]').exists()
    ).toBe(false);
  });
});

describe('RankingDeBarras', () => {
  const itens = Array.from({ length: 10 }, (_, i) => ({
    id: `t${i}`,
    nome: `Tema ${i}`,
    valor: 100 - i * 5,
    pct: 10,
  }));

  it('shows the first 8 and opens the rest on demand', async () => {
    const wrapper = mount(RankingDeBarras, {
      props: { itens, rotulo: 'Temas' },
    });
    expect(wrapper.findAll('[data-item]')).toHaveLength(8);
    await wrapper.get('[data-ver-todos]').trigger('click');
    expect(wrapper.findAll('[data-item]')).toHaveLength(10);
  });

  it('never shows a raw id for an item without a name', () => {
    const wrapper = mount(RankingDeBarras, {
      props: { itens: [{ id: 'cru_123', valor: 3 }], rotulo: 'Temas' },
    });
    expect(wrapper.text()).not.toContain('cru_123');
    expect(wrapper.text()).toContain('AGENTS.DESEMPENHO2.A.COMUM.SEM_NOME');
  });

  it('emits the chosen item when clickable', async () => {
    const wrapper = mount(RankingDeBarras, {
      props: { itens, rotulo: 'Temas', clicavel: true },
    });
    await wrapper.get('[data-item] button').trigger('click');
    expect(wrapper.emitted('escolher')[0][0].id).toBe('t0');
  });
});

describe('MapaDeCalor', () => {
  it('leaves zero cells empty and rings only the peak', () => {
    const mapa = Array.from({ length: 7 }, () => Array(24).fill(0));
    mapa[3][16] = 9;
    mapa[0][10] = 2;
    const wrapper = mount(MapaDeCalor, { props: { mapa } });
    expect(wrapper.get('[data-celula="0-0"]').text()).toBe('');
    expect(wrapper.findAll('[data-pico]')).toHaveLength(1);
    expect(wrapper.get('[data-pico]').attributes('data-celula')).toBe('3-16');
    expect(wrapper.get('[data-total-geral]').text()).toBe('11');
  });
});

describe('EstadoDoPainel', () => {
  const montar = props =>
    mount(EstadoDoPainel, {
      props: { nome: 'Duda', podeGerenciar: true, ...props },
    });

  it.each(Object.keys(VARIANTES))(
    'renders the %s variant with one phrase',
    variante => {
      const wrapper = montar({ variante });
      expect(wrapper.get(`[data-estado="${variante}"]`).text()).toContain(
        `AGENTS.DESEMPENHO.ESTADO.${VARIANTES[variante].chave}`
      );
      const botoes = wrapper.findAll('[data-acao-estado]');
      const semBotao =
        VARIANTES[variante].faixa || VARIANTES[variante].semBotao;
      expect(botoes).toHaveLength(semBotao ? 0 : 1);
    }
  );

  it.each(
    Object.keys(VARIANTES).filter(
      v => !VARIANTES[v].faixa && !VARIANTES[v].semBotao
    )
  )('the %s button emits its variant', async variante => {
    const wrapper = montar({ variante });
    await wrapper.get('[data-acao-estado]').trigger('click');
    expect(wrapper.emitted('acao')[0]).toEqual([variante]);
  });

  it('whoever only sees gets no button to turn reading on', () => {
    const wrapper = montar({
      variante: 'leitura_desligada',
      podeGerenciar: false,
    });
    expect(wrapper.text()).toContain('LEITURA_DESLIGADA_SEM_ACESSO');
    expect(wrapper.find('[data-acao-estado]').exists()).toBe(false);
  });

  it('with the key refused, whoever only sees is asked to call the admin and can go to the numbers (#2301)', () => {
    const wrapper = montar({
      variante: 'chave_recusada',
      podeGerenciar: false,
    });
    expect(wrapper.text()).toContain('CHAVE_RECUSADA_SEM_ACESSO');
    expect(wrapper.get('[data-acao-estado]').text()).toBe(
      'AGENTS.DESEMPENHO.ESTADO.CHAVE_RECUSADA_SEM_ACESSO_BOTAO'
    );
  });

  it('with an empty panel, only the button that acts outside it stays (#2301)', () => {
    expect(
      montar({ variante: 'teto', vazio: true })
        .find('[data-acao-estado]')
        .exists()
    ).toBe(false);
    expect(
      montar({ variante: 'chave_recusada', vazio: true })
        .find('[data-acao-estado]')
        .exists()
    ).toBe(true);
    expect(
      montar({ variante: 'sem_ia', vazio: true, podeGerenciar: false })
        .find('[data-acao-estado]')
        .exists()
    ).toBe(false);
  });

  it('without the AI key, whoever only sees can still go to the numbers', () => {
    const wrapper = montar({ variante: 'sem_ia', podeGerenciar: false });
    expect(wrapper.get('[data-acao-estado]').text()).toBe(
      'AGENTS.DESEMPENHO.ESTADO.SEM_IA_SEM_ACESSO_BOTAO'
    );
  });
});

describe('AgenteSemana — Ver tudo', () => {
  const montar = props =>
    mount(AgenteSemana, {
      props: {
        nome: 'Duda',
        numeros: { respondidas: 3, passadas: 1, resolvidas: 2 },
        ...props,
      },
    });

  it('shows the link only with the panel address (flag on)', async () => {
    expect(montar().find('[data-ver-tudo]').exists()).toBe(false);
    const wrapper = montar({ hrefDesempenho: '/app/desempenho' });
    const link = wrapper.get('[data-ver-tudo]');
    expect(link.attributes('href')).toBe('/app/desempenho');
    expect(link.text()).toBe('AGENTS.DESEMPENHO.VER_TUDO');
    await link.trigger('click');
    expect(wrapper.emitted('desempenho')).toHaveLength(1);
  });

  it('keeps the link on the empty week too', () => {
    const wrapper = montar({
      numeros: { respondidas: 0, passadas: 0, resolvidas: 0 },
      hrefDesempenho: '/app/desempenho',
    });
    expect(wrapper.find('[data-semana-vazia] [data-ver-tudo]').exists()).toBe(
      true
    );
  });
});
