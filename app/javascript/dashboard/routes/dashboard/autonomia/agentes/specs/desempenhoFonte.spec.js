import fs from 'fs';
import path from 'path';
import { mount } from '@vue/test-utils';
import {
  PERIODOS,
  PERIODO_PADRAO,
  SITUACOES,
  comSituacao,
  comporPainel,
  fonteDoPainel,
  painelDemo,
  painelVazio,
  semAnuncio,
} from '../utils/desempenhoFonte';
import {
  delta,
  diaDe,
  maiorTravaDaCompra,
  sugestaoPrincipal,
  fechou,
  grupoDoResultado,
  hrefDaConversa,
  marcoMaisLonge,
  nomeDe,
  nomeDoCorte,
  pct,
} from '../utils/desempenhoContrato';
import demo from '../utils/desempenhoDemo.json';
import DemoInterruptor from '../components/desempenho/DemoInterruptor.vue';

// #2226 v2 (desenho §6) — a fonte do painel de desempenho: o pacote da vida real é composto por
// período, sem ele cai na demonstração, a demonstração serve os estados (b) com anúncios e (a) sem,
// e os invariantes do contrato valem na demonstração de todo período. Os dados aqui são inventados;
// o arquivo da vida real só é conferido quando existe nesta máquina (nunca é versionado).

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
const soma = (lista, campo) =>
  lista.reduce((acc, item) => acc + (item[campo] || 0), 0);
const kpi = (painel, id) => painel.kpis.find(item => item.id === id);

const pctsForaDaFaixa = (valor, caminho = '') => {
  if (Array.isArray(valor))
    return valor.flatMap((item, i) =>
      pctsForaDaFaixa(item, `${caminho}[${i}]`)
    );
  if (!valor || typeof valor !== 'object') return [];
  return Object.entries(valor).flatMap(([chave, item]) => {
    const ehPct = chave === 'pct' || chave.endsWith('_pct');
    const fora =
      ehPct &&
      item !== null &&
      (typeof item !== 'number' || item < 0 || item > 100);
    return [
      ...(fora ? [`${caminho}.${chave}`] : []),
      ...pctsForaDaFaixa(item, `${caminho}.${chave}`),
    ];
  });
};

// Os invariantes do §6.3, conferidos num Painel já composto.
const falhasDoContrato = painel => {
  const falhas = [];
  const confere = (ok, nome) => {
    if (!ok) falhas.push(nome);
  };
  const { catalogo, procuras } = painel;
  const base = painel.meta.base.procuras;
  const reais = procuras.filter(procura => !procura.teste);
  confere(painel.versao === 2, 'versao');
  confere(
    JSON.stringify(painel.kpis.map(item => item.id)) === JSON.stringify(KPIS),
    'kpis na ordem'
  );
  confere(soma(painel.evolucao.pontos, 'procuras') === base, 'evolução');
  confere(
    painel.horarios.mapa.flat().reduce((a, b) => a + b, 0) === base,
    'mapa'
  );
  confere(
    painel.evolucao.pontos.every(
      ponto => ponto.com_anuncio + ponto.sem_anuncio === ponto.procuras
    ),
    'com + sem anúncio'
  );
  confere(kpi(painel, 'procuras').valor === reais.length, 'kpi procuras');
  confere(
    kpi(painel, 'fecharam').valor ===
      soma(kpi(painel, 'fecharam').composicao || [], 'valor'),
    'composição de fecharam'
  );
  const etapas = painel.funil.etapas.map(etapa => etapa.procuras);
  confere(
    etapas.every((n, i) => i === 0 || n <= etapas[i - 1]),
    'funil decresce'
  );
  confere(soma(painel.origem.grupos, 'procuras') === base, 'origem soma');
  const ids = [
    ['temas', 'tema_id'],
    ['quem', 'quem_id'],
    ['origens', 'origem_id'],
    ['resultados', 'resultado_id'],
  ];
  ids.forEach(([tipo, campo]) =>
    confere(
      procuras.every(procura => procura[campo] in catalogo[tipo]),
      `${campo} no catálogo`
    )
  );
  const listas = [
    ['motivos', 'motivo_ids'],
    ['regras', 'regra_ids'],
    ['marcos', 'marcos'],
  ];
  listas.forEach(([tipo, campo]) =>
    confere(
      procuras.every(procura =>
        procura[campo].every(id => id in catalogo[tipo])
      ),
      `${campo} no catálogo`
    )
  );
  confere(
    procuras.every(procura =>
      Object.entries(procura.cortes).every(
        ([corte, valor]) => valor in (catalogo.cortes[corte] || {})
      )
    ),
    'cortes no catálogo'
  );
  confere(pctsForaDaFaixa(painel).length === 0, 'pct entre 0 e 100');
  return falhas;
};

// Pacote mínimo inventado: dois períodos, três procuras (uma de teste, uma fora do período curto).
const procura = (conversa, inicio, extra = {}) => ({
  conversa,
  procura: 1,
  inicio,
  teste: false,
  quem_id: 'q1',
  origem_id: 'o1',
  anuncio_id: null,
  pedido_id: 'p1',
  tema_id: 't1',
  cortes: {},
  marcos: [],
  resultado_id: 'r1',
  motivo_ids: [],
  qualidade_id: 'acertou',
  regra_ids: [],
  perda_evitavel: false,
  precisava_pessoa: false,
  teve_pessoa: false,
  resumo: 'Pediu um orçamento.',
  ...extra,
});
const resumoDoPeriodo = (chave, inicio, fim) => ({
  versao: 2,
  meta: { fonte: 'vida_real', situacao: null, periodo: { chave, inicio, fim } },
  kpis: [],
});
const PACOTE = {
  versao: 2,
  pacote: true,
  catalogo: { temas: { t1: 'Prazo' } },
  procuras: [
    procura(10, '2026-10-01T09:00'),
    procura(11, '2026-10-20T00:00'),
    procura(12, '2026-10-26T23:59', { teste: true }),
  ],
  periodos: {
    7: resumoDoPeriodo('7', '2026-10-20', '2026-10-26'),
    30: resumoDoPeriodo('30', '2026-09-27', '2026-10-26'),
  },
};
const resposta = (corpo, ok = true) => ({ ok, json: async () => corpo });

describe('desempenhoContrato — helpers', () => {
  const catalogo = demo.catalogo;

  it('finds business names in the catalogue and never returns the raw id', () => {
    expect(nomeDe(catalogo, 'temas', 'montagem')).toBe('Montagem');
    expect(nomeDe(catalogo, 'resultados', 'vai_pensar')).toBe('Vai pensar');
    expect(nomeDe(catalogo, 'origens', 'site')).toBe('Site');
    expect(nomeDe(catalogo, 'regras', 'R-CURTO')).toBe('Resposta curta');
    expect(nomeDe(catalogo, 'temas', 'nao_existe')).toBeNull();
    expect(nomeDe(catalogo, 'tipo_desconhecido', 'montagem')).toBeNull();
    expect(nomeDe(null, 'temas', 'montagem')).toBeNull();
    expect(nomeDoCorte(catalogo, 'produto', 'sofa')).toBe('Sofá');
    expect(nomeDoCorte(catalogo, 'produto', 'nada')).toBeNull();
  });

  it('knows the result group and whether a request closed', () => {
    expect(grupoDoResultado(catalogo, 'pedido_confirmado')).toBe('fechou');
    expect(grupoDoResultado(catalogo, 'duvida_resolvida')).toBe('resolveu');
    expect(grupoDoResultado(catalogo, 'x')).toBeNull();
    expect(fechou(catalogo, { resultado_id: 'pagamento_enviado' })).toBe(true);
    expect(fechou(catalogo, { resultado_id: 'vai_pensar' })).toBe(false);
  });

  it('returns the furthest funnel step reached, also for steps made of several milestones', () => {
    const etapas = [
      { id: 'pedido' },
      { id: 'escolheu' },
      { id: 'confirmou', marcos: ['confirmou', 'login'] },
      { id: 'pago' },
    ];
    expect(marcoMaisLonge(etapas, ['pedido', 'escolheu'])).toBe('escolheu');
    expect(marcoMaisLonge(etapas, ['pedido', 'login'])).toBe('confirmou');
    expect(marcoMaisLonge(etapas, ['outro'])).toBeNull();
    expect(marcoMaisLonge(etapas, undefined)).toBeNull();
  });

  it('finds the biggest blocker among purchase requests, without tests or closed ones', () => {
    const catalogoDaTrava = {
      resultados: {
        pago: { nome: 'Pago', grupo: 'fechou' },
        sumiu: { nome: 'Sumiu', grupo: 'parou' },
        caro: { nome: 'Achou caro', grupo: 'parou' },
      },
    };
    const procuras = [
      { compra: true, resultado_id: 'pago' },
      { compra: true, resultado_id: 'sumiu' },
      { compra: true, resultado_id: 'sumiu' },
      { compra: true, resultado_id: 'caro' },
      { compra: true, resultado_id: 'caro', teste: true },
      { compra: false, resultado_id: 'caro' },
    ];
    expect(maiorTravaDaCompra({ catalogo: catalogoDaTrava, procuras })).toEqual(
      {
        id: 'sumiu',
        nome: 'Sumiu',
        n: 2,
        m: 4,
        pct: 50,
      }
    );
    expect(maiorTravaDaCompra({ catalogo, procuras: [] })).toBeNull();
  });

  it('starts with the ready suggestion of biggest estimated gain', () => {
    const recomendacoes = [
      { id: 'a', pronto: 'ja_da', ganho: { fechamentos: 2 } },
      { id: 'b', pronto: 'falta_dado', ganho: { fechamentos: 9 } },
      { id: 'c', pronto: 'ja_da', ganho: { fechamentos: 5 } },
      { id: 'd', pronto: 'ja_da', ganho: { fechamentos: null } },
    ];
    expect(sugestaoPrincipal({ recomendacoes }).id).toBe('c');
    expect(sugestaoPrincipal({ recomendacoes: [] })).toBeNull();
  });

  it('never lets a full-history gain beat a gain of the chosen period', () => {
    const recomendacoes = [
      { id: 'a', pronto: 'ja_da', ganho: { fechamentos: 19, historico: true } },
      { id: 'b', pronto: 'ja_da', ganho: { fechamentos: 4, historico: false } },
    ];
    expect(sugestaoPrincipal({ recomendacoes }).id).toBe('b');
  });

  it('computes a percentage with one decimal and null when there is no base', () => {
    expect(pct(25, 135)).toBe(18.5);
    expect(pct(1, 3)).toBe(33.3);
    expect(pct(0, 5)).toBe(0);
    expect(pct(5, 0)).toBeNull();
  });

  it('tells whether the change since the previous period is good or bad', () => {
    expect(delta({ valor: 10, anterior: null, melhor: 'subir' })).toBeNull();
    expect(delta({ valor: 12, anterior: 10, melhor: 'subir' })).toEqual({
      diferenca: 2,
      sentido: 'favoravel',
      unidade: 'valor',
    });
    expect(delta({ valor: 12, anterior: 10, melhor: 'descer' })).toEqual({
      diferenca: 2,
      sentido: 'desfavoravel',
      unidade: 'valor',
    });
    expect(delta({ valor: 8, anterior: 10, melhor: 'descer' }).sentido).toBe(
      'favoravel'
    );
    expect(delta({ valor: 10, anterior: 10, melhor: 'subir' }).sentido).toBe(
      'neutro'
    );
    expect(delta({ valor: 9, anterior: 10, melhor: null }).sentido).toBe(
      'neutro'
    );
  });

  it('links to the conversation by the number shown in the inbox and reads the day', () => {
    const router = {
      resolve: vi.fn(() => ({ href: '/app/accounts/1/conversations/312' })),
    };
    expect(hrefDaConversa(router, 312)).toBe(
      '/app/accounts/1/conversations/312'
    );
    expect(router.resolve).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { conversation_id: 312 },
    });
    expect(diaDe('2026-06-30T10:43')).toBe('2026-06-30');
  });
});

describe('comporPainel', () => {
  it('joins the period summary with the catalogue and the requests of that period', () => {
    const painel = comporPainel(PACOTE, '7');
    expect(painel.meta.periodo.chave).toBe('7');
    expect(painel.catalogo).toBe(PACOTE.catalogo);
    expect(painel.procuras.map(item => item.conversa)).toEqual([11, 12]);
  });

  it('keeps both ends of the period and falls back to the default period', () => {
    expect(comporPainel(PACOTE, '30').procuras).toHaveLength(3);
    expect(comporPainel(PACOTE, 'nao_existe').meta.periodo.chave).toBe(
      PERIODO_PADRAO
    );
  });
});

describe('fonteDoPainel — vida real ou demonstração', () => {
  const VIDA_REAL = { fonte: 'vida_real' };

  it('never reads the real file outside the development environment', async () => {
    const buscar = vi.fn(async () => resposta(PACOTE));
    const fonte = fonteDoPainel({ buscar, vidaRealPermitida: false });
    const painel = await fonte.carregar({ periodo: '7', demo: VIDA_REAL });
    expect(buscar).not.toHaveBeenCalled();
    expect(painel.meta.fonte).toBe('demo');
    expect(await fonte.temVidaReal()).toBe(false);
  });

  it('opens on the real package when the address does not choose a source', async () => {
    const buscar = vi.fn(async () => resposta(PACOTE));
    const painel = await fonteDoPainel({
      buscar,
      vidaRealPermitida: true,
    }).carregar({ periodo: '7' });
    expect(buscar).toHaveBeenCalledTimes(1);
    expect(painel.meta.fonte).toBe('vida_real');
  });

  it('falls back to the demo without a warning when nobody asked for the real file', async () => {
    const buscar = vi.fn(async () => ({ ok: false }));
    const painel = await fonteDoPainel({
      buscar,
      vidaRealPermitida: true,
    }).carregar({ periodo: '7' });
    expect(painel.meta.fonte).toBe('demo');
    expect(painel.meta.aviso_fonte).toBeUndefined();
  });

  it('never reads the real file when the address asks for the demo', async () => {
    const buscar = vi.fn(async () => resposta(PACOTE));
    const painel = await fonteDoPainel({
      buscar,
      vidaRealPermitida: true,
    }).carregar({ periodo: '7', demo: { fonte: 'demo' } });
    expect(buscar).not.toHaveBeenCalled();
    expect(painel.meta.fonte).toBe('demo');
  });

  it('uses the real package when the file answers', async () => {
    const buscar = vi.fn(async () => resposta(PACOTE));
    const fonte = fonteDoPainel({ buscar });
    const painel = await fonte.carregar({ periodo: '7', demo: VIDA_REAL });
    expect(buscar).toHaveBeenCalledWith('/desempenho-vida-real.json', {
      cache: 'no-cache',
    });
    expect(painel.meta.fonte).toBe('vida_real');
    expect(painel.procuras).toHaveLength(2);
    expect(await fonte.temVidaReal()).toBe(true);
  });

  it('reads the file only once per source', async () => {
    const buscar = vi.fn(async () => resposta(PACOTE));
    const fonte = fonteDoPainel({ buscar });
    await fonte.carregar({ periodo: '7', demo: VIDA_REAL });
    await fonte.carregar({ periodo: '30', demo: VIDA_REAL });
    expect(buscar).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['missing file', async () => resposta(null, false), 'sem_arquivo'],
    ['network error', async () => Promise.reject(new Error('rede')), 'leitura'],
    ['not a package', async () => resposta({ versao: 1 }), 'formato'],
  ])(
    'falls back to the demonstration on %s and says why',
    async (_caso, buscar, falha) => {
      const fonte = fonteDoPainel({ buscar });
      const painel = await fonte.carregar({ periodo: '30', demo: VIDA_REAL });
      expect(painel.meta.fonte).toBe('demo');
      expect(painel.meta.aviso_fonte).toBe(falha);
      expect(await fonte.temVidaReal()).toBe(false);
    }
  );

  it('shows the demonstration when asked, without reading the real file', async () => {
    const buscar = vi.fn(async () => resposta(PACOTE));
    const painel = await fonteDoPainel({ buscar }).carregar({
      periodo: '7',
      demo: { fonte: 'demo' },
    });
    expect(painel.meta.fonte).toBe('demo');
    expect(buscar).not.toHaveBeenCalled();
  });

  it('applies the chosen situation and ignores an unknown one', async () => {
    const buscar = async () => resposta(null, false);
    const fonte = fonteDoPainel({ buscar });
    const comEstado = await fonte.carregar({ demo: { situacao: 'lendo' } });
    expect(comEstado.meta.situacao).toBe('lendo');
    const semEstado = await fonte.carregar({ demo: { situacao: 'inventada' } });
    expect(semEstado.meta.situacao).toBeNull();
    expect(comSituacao(demo, 'pouco')).not.toBe(demo);
    expect(SITUACOES).toContain('sem_conversas');
  });
});

describe('fonteDoPainel — API (#2251)', () => {
  const PEDIDO = {
    accountId: 1,
    agentId: '9',
    origem: 'webhook',
    periodo: '7',
  };
  const daApi = {
    versao: 2,
    kpis: [],
    meta: { fonte: 'api', periodo: { chave: '7' } },
  };
  const apiCom = painel => ({
    painel: vi.fn(async () => ({ data: painel })),
    exportar: vi.fn(async () => ({ data: new Blob(['x']) })),
  });

  it('reads the API by default and never the local file', async () => {
    const buscar = vi.fn(async () => resposta(PACOTE));
    const api = apiCom(daApi);
    const painel = await fonteDoPainel({
      buscar,
      vidaRealPermitida: true,
      api,
    }).carregar(PEDIDO);
    expect(api.painel).toHaveBeenCalledWith({
      accountId: 1,
      agentId: '9',
      origem: 'webhook',
      periodo: '7',
    });
    expect(buscar).not.toHaveBeenCalled();
    expect(painel.meta.fonte).toBe('api');
  });

  it('still opens the demonstration or the local file when the address asks', async () => {
    const api = apiCom(daApi);
    const fonte = fonteDoPainel({
      buscar: async () => resposta(PACOTE),
      vidaRealPermitida: true,
      api,
    });
    expect(
      (await fonte.carregar({ ...PEDIDO, demo: { fonte: 'demo' } })).meta.fonte
    ).toBe('demo');
    expect(
      (await fonte.carregar({ ...PEDIDO, demo: { fonte: 'vida_real' } })).meta
        .fonte
    ).toBe('vida_real');
    expect(api.painel).not.toHaveBeenCalled();
  });

  it('returns an empty panel with the situation when the agent has no reading', async () => {
    const painel = await fonteDoPainel({
      api: apiCom({
        versao: 2,
        vazio: true,
        meta: { situacao: 'leitura_desligada' },
      }),
    }).carregar(PEDIDO);
    expect(painel).toMatchObject({
      vazio: true,
      meta: {
        fonte: 'api',
        situacao: 'leitura_desligada',
        periodo: { chave: '7' },
      },
    });
    expect(painel.meta.aviso_fonte).toBeUndefined();
  });

  it('never falls back to the demonstration when the API fails', async () => {
    const api = {
      painel: vi.fn(async () => Promise.reject(new Error('rede'))),
    };
    const painel = await fonteDoPainel({ api }).carregar(PEDIDO);
    expect(painel.vazio).toBe(true);
    expect(painel.meta.fonte).toBe('api');
    expect(painel.meta.aviso_fonte).toBe('api');
  });

  it('exports through the API and only a panel with numbers', async () => {
    const api = apiCom(daApi);
    const fonte = fonteDoPainel({ api });
    const painel = daApi;
    const arquivo = await fonte.exportar(painel, 'xlsx', PEDIDO);
    expect(arquivo.nome).toBe('desempenho-7.xlsx');
    expect(await arquivo.baixar()).toBeInstanceOf(Blob);
    expect(api.exportar).toHaveBeenCalledWith({
      accountId: 1,
      agentId: '9',
      origem: 'webhook',
      periodo: '7',
      formato: 'xlsx',
    });
    expect(await fonte.exportar(painelVazio('7'), 'pdf', PEDIDO)).toBeNull();
  });
});

describe('demonstração — invariantes em todo período', () => {
  it('the fixture is the 30-day period with ads (state b)', async () => {
    const painel = await painelDemo({ periodo: '30' });
    expect(painel).toBe(demo);
    expect(painel.meta.anuncios_ligados).toBe(true);
    expect(painel.origem.anuncios.length).toBeGreaterThan(0);
    expect(falhasDoContrato(painel)).toEqual([]);
  });

  it.each(PERIODOS)(
    'period %s: the parts close with the whole',
    async periodo => {
      const painel = await painelDemo({ periodo });
      expect(painel.meta.periodo.chave).toBe(periodo);
      expect(painel.meta.fonte).toBe('demo');
      expect(falhasDoContrato(painel)).toEqual([]);
      const { inicio, fim } = painel.meta.periodo;
      expect(
        painel.procuras.every(
          item => diaDe(item.inicio) >= inicio && diaDe(item.inicio) <= fim
        )
      ).toBe(true);
    }
  );

  it('the 7-day period is smaller than the 30-day one and compares with the week before', async () => {
    const sete = await painelDemo({ periodo: '7' });
    expect(sete.meta.base.procuras).toBeLessThan(demo.meta.base.procuras);
    expect(sete.evolucao.unidade).toBe('dia');
    expect(kpi(sete, 'procuras').anterior).not.toBeNull();
    const tudo = await painelDemo({ periodo: 'tudo' });
    expect(tudo.evolucao.unidade).toBe('semana');
    expect(tudo.meta.periodo.anterior).toBeNull();
    expect(tudo.avisos.map(aviso => aviso.id)).not.toContain('so_periodo_todo');
    expect(sete.avisos.map(aviso => aviso.id)).toContain('so_periodo_todo');
  });
});

describe('demonstração sem anúncio (estado a)', () => {
  it.each(PERIODOS)(
    'period %s: no ad anywhere and the totals do not change',
    async periodo => {
      const comAnuncio = await painelDemo({ periodo });
      const painel = await painelDemo({ periodo, anuncios: '0' });
      expect(painel.meta.anuncios_ligados).toBe(false);
      expect(painel.origem.anuncios_ligados).toBe(false);
      expect(painel.origem.comparacao).toBeNull();
      expect(painel.origem.anuncios).toEqual([]);
      expect(
        painel.origem.grupos.every(grupo => grupo.tipo !== 'anuncio')
      ).toBe(true);
      expect(
        Object.values(painel.catalogo.origens).every(
          item => item.tipo !== 'anuncio'
        )
      ).toBe(true);
      expect(painel.procuras.every(item => item.anuncio_id === null)).toBe(
        true
      );
      expect(
        painel.evolucao.pontos.every(ponto => ponto.com_anuncio === 0)
      ).toBe(true);
      expect(
        painel.recomendacoes.every(item => item.frente !== 'anuncio')
      ).toBe(true);
      expect(painel.avisos.map(aviso => aviso.id)).toContain('sem_anuncio');
      expect(painel.meta.base).toEqual(comAnuncio.meta.base);
      expect(falhasDoContrato(painel)).toEqual([]);
    }
  );

  it('moves the ad requests to the biggest group without ads and recomputes its rate', () => {
    const painel = semAnuncio(demo);
    const antes = demo.origem.grupos;
    const maior = antes.find(grupo => grupo.tipo !== 'anuncio');
    const deAnuncio = antes.filter(grupo => grupo.tipo === 'anuncio');
    const depois = painel.origem.grupos.find(grupo => grupo.id === maior.id);
    expect(depois.procuras).toBe(maior.procuras + soma(deAnuncio, 'procuras'));
    expect(depois.taxa_pct).toBe(pct(depois.fecharam, depois.compra));
    const comparacao = painel.comparacoes.find(
      item => item.recorte === 'origem'
    );
    const lado = [comparacao.a, comparacao.b].find(
      item => item.id === maior.id
    );
    expect(lado).toMatchObject({ n: depois.fecharam, m: depois.compra });
  });

  it('does not change the original demonstration', () => {
    const copia = JSON.stringify(demo);
    semAnuncio(demo);
    comSituacao(demo, 'teto');
    expect(JSON.stringify(demo)).toBe(copia);
  });

  it('accepts the boolean too', async () => {
    const painel = await painelDemo({ periodo: '30', anuncios: false });
    expect(painel.meta.anuncios_ligados).toBe(false);
  });
});

describe('exportar', () => {
  const buscarCom = ok => vi.fn(async () => ({ ok }));

  it('returns the file of the period when it exists', async () => {
    const buscar = buscarCom(true);
    const arquivo = await fonteDoPainel({ buscar }).exportar(demo, 'pdf');
    expect(arquivo).toEqual({
      url: '/desempenho-demo-30.pdf',
      nome: 'desempenho-demo-30.pdf',
    });
    expect(buscar).toHaveBeenCalledWith('/desempenho-demo-30.pdf', {
      method: 'HEAD',
      cache: 'no-cache',
    });
  });

  it('names the real file by period', async () => {
    const painel = comporPainel(PACOTE, '7');
    const arquivo = await fonteDoPainel({ buscar: buscarCom(true) }).exportar(
      painel,
      'xlsx'
    );
    expect(arquivo.nome).toBe('desempenho-vida-real-7.xlsx');
  });

  it('returns null without a file, with an unknown format or for a changed demonstration', async () => {
    expect(
      await fonteDoPainel({ buscar: buscarCom(false) }).exportar(demo, 'pdf')
    ).toBeNull();
    const fonte = fonteDoPainel({ buscar: buscarCom(true) });
    expect(await fonte.exportar(demo, 'csv')).toBeNull();
    expect(await fonte.exportar(semAnuncio(demo), 'pdf')).toBeNull();
    expect(await fonte.exportar(comSituacao(demo, 'lendo'), 'xlsx')).toBeNull();
    expect(await fonte.exportar(null, 'pdf')).toBeNull();
    const falha = fonteDoPainel({
      buscar: async () => Promise.reject(new Error('rede')),
    });
    expect(await falha.exportar(demo, 'pdf')).toBeNull();
  });
});

describe('dados inventados', () => {
  it('the demonstration is marked as made-up and uses placeholder names', () => {
    expect(demo.meta.fonte).toBe('demo');
    expect(demo.meta.conta.nome).toBe('Loja Exemplo');
    expect(demo.meta.agente.nome).toBe('Agente Exemplo');
  });
});

// O pacote real só existe na máquina de quem gerou (public/desempenho-*, fora do git).
const ARQUIVO_REAL = path.resolve('public/desempenho-vida-real.json');
describe.skipIf(!fs.existsSync(ARQUIVO_REAL))('pacote da vida real', () => {
  it.each(PERIODOS)('period %s keeps the contract invariants', periodo => {
    const pacote = JSON.parse(fs.readFileSync(ARQUIVO_REAL, 'utf8'));
    const painel = comporPainel(pacote, periodo);
    expect(painel.meta.fonte).toBe('vida_real');
    expect(falhasDoContrato(painel)).toEqual([]);
  });

  it('shares no summary text with the demonstration', () => {
    const pacote = JSON.parse(fs.readFileSync(ARQUIVO_REAL, 'utf8'));
    const reais = new Set(pacote.procuras.map(item => item.resumo));
    expect(demo.procuras.filter(item => reais.has(item.resumo))).toEqual([]);
  });
});

describe('DemoInterruptor', () => {
  const montar = props =>
    mount(DemoInterruptor, { props: { fonte: 'demo', ...props } });

  it('offers source, ads and situation, with no native select', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-demo-fonte]').exists()).toBe(true);
    expect(wrapper.find('[data-demo-anuncio]').exists()).toBe(true);
    expect(wrapper.find('[data-demo-situacao]').exists()).toBe(true);
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('hides the ads choice with real data and hides everything with the API', () => {
    expect(
      montar({ fonte: 'vida_real' }).find('[data-demo-anuncio]').exists()
    ).toBe(false);
    expect(montar({ fonte: 'api' }).find('[data-demo]').exists()).toBe(false);
  });

  it('sends each choice to the address', async () => {
    const wrapper = montar();
    const [fonte, anuncio, situacao] = wrapper.findAllComponents({
      name: 'ChoiceSelect',
    });
    await fonte.vm.$emit('update:modelValue', 'vida_real');
    await anuncio.vm.$emit('update:modelValue', '0');
    await situacao.vm.$emit('update:modelValue', 'teto');
    await situacao.vm.$emit('update:modelValue', 'normal');
    expect(wrapper.emitted('trocar')).toEqual([
      [{ fonte: 'vida_real' }],
      [{ anuncio: '0' }],
      [{ estado: 'teto' }],
      [{ estado: undefined }],
    ]);
  });

  it('turns off the real data choice when the file is not on this computer', () => {
    const wrapper = montar({ vidaRealDisponivel: false });
    const [fonte] = wrapper.findAllComponents({ name: 'ChoiceSelect' });
    const opcao = fonte
      .props('options')
      .find(item => item.value === 'vida_real');
    expect(opcao.disabled).toBe(true);
    expect(opcao.hint).toBeTruthy();
  });
});
