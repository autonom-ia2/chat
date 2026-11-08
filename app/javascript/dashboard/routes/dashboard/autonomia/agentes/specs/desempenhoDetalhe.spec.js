import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import AbaDetalhe from '../components/desempenho/detalhe/AbaDetalhe.vue';
import TabelaProcuras from '../components/desempenho/detalhe/TabelaProcuras.vue';
import TabelaPorPeriodo from '../components/desempenho/detalhe/TabelaPorPeriodo.vue';
import TabelaDoPainel from '../components/desempenho/detalhe/TabelaDoPainel.vue';
import demo from '../utils/desempenhoDemo.json';
import {
  FILTROS_VAZIOS,
  enderecoDaAba,
  enderecoDosFiltros,
  filtrarProcuras,
  filtrosDoEndereco,
  filtrosValidos,
  opcoesDosFiltros,
  ordenar,
  paginar,
  resumoDasProcuras,
  tabelaDoEndereco,
  textoDeBusca,
  totalDoPeriodo,
} from '../utils/desempenhoDetalhe';

// #2226 v2 — aba Detalhe: filtro, busca sem acento, ordenação, paginação, total do período, filtros
// ↔ endereço e o link da conversa na linha. Dados inventados e genéricos.
const rota = vi.hoisted(() => ({ atual: null }));
const router = vi.hoisted(() => ({
  replace: vi.fn(),
  resolve: vi.fn(destino => ({
    href: `/app/conversations/${destino.params.conversation_id}`,
  })),
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota.atual,
  useRouter: () => router,
}));

const catalogo = {
  temas: { entrega: 'Prazo de entrega', preco: 'Preço' },
  marcos: { pediu: 'Pediu algo', recebeu: 'Recebeu proposta', pagou: 'Pagou' },
  resultados: {
    pago: { nome: 'Pagamento enviado', grupo: 'fechou' },
    sumiu: { nome: 'Sumiu', grupo: 'parou' },
    duvida: { nome: 'Dúvida resolvida', grupo: 'resolveu' },
  },
  motivos: { caro: 'Achou caro' },
  regras: {},
  quem: {},
  origens: {
    anuncio: { nome: 'Anúncio', tipo: 'anuncio' },
    site: { nome: 'Site', tipo: 'sem_anuncio' },
  },
  cortes: { pedido: { comprar: 'Quer comprar', duvida: 'Tirar dúvida' } },
};

const procura = (conversa, extra = {}) => ({
  conversa,
  procura: 1,
  inicio: '2026-01-10T10:00',
  teste: false,
  quem_id: null,
  origem_id: 'site',
  anuncio_id: null,
  pedido_id: 'comprar',
  tema_id: 'entrega',
  cortes: { pedido: 'comprar' },
  marcos: ['pediu'],
  resultado_id: 'sumiu',
  motivo_ids: [],
  qualidade_id: 'acertou',
  regra_ids: [],
  perda_evitavel: false,
  precisava_pessoa: false,
  teve_pessoa: false,
  resumo: 'Perguntou o prazo.',
  ...extra,
});

const procuras = [
  procura(101, {
    inicio: '2026-01-12T09:00',
    resultado_id: 'pago',
    marcos: ['pediu', 'recebeu', 'pagou'],
    resumo: 'Pediu orçamento e recebeu o link.',
  }),
  procura(102, {
    inicio: '2026-01-11T15:30',
    tema_id: 'preco',
    origem_id: 'anuncio',
    perda_evitavel: true,
    marcos: ['pediu', 'recebeu'],
    resumo: 'Achou o PREÇO alto.',
  }),
  procura(103, {
    procura: 2,
    inicio: '2026-01-10T20:15',
    precisava_pessoa: true,
    cortes: { pedido: 'duvida' },
    resultado_id: 'duvida',
    qualidade_id: 'erro_grave',
  }),
  procura(104, { teste: true, resumo: 'Teste interno.' }),
];

const etapas = [
  { id: 'pediu', nome: 'Pediu algo', procuras: 3 },
  { id: 'recebeu', nome: 'Recebeu proposta', procuras: 2 },
  { id: 'pagou', nome: 'Pagou', procuras: 1 },
];

const painel = {
  versao: 2,
  meta: {
    nomes: { compra: 'Pedidos de compra', fechou: 'Fecharam' },
    anuncios_ligados: false,
    base: { procuras: 3 },
  },
  catalogo,
  funil: { etapas },
  cortes: [{ id: 'pedido', nome: 'O que pediram' }],
  evolucao: {
    unidade: 'dia',
    pontos: [
      {
        inicio: '2026-01-10',
        fim: '2026-01-10',
        procuras: 1,
        conversas_novas: 1,
        compra: 0,
        fecharam: 0,
        precisavam_pessoa: 1,
        tiveram_pessoa: 0,
        com_anuncio: 0,
        sem_anuncio: 1,
        parcial: false,
      },
      {
        inicio: '2026-01-11',
        fim: '2026-01-11',
        procuras: 2,
        conversas_novas: 2,
        compra: 2,
        fecharam: 1,
        precisavam_pessoa: 0,
        tiveram_pessoa: 0,
        com_anuncio: 1,
        sem_anuncio: 1,
        parcial: true,
      },
    ],
  },
  temas: { ranking: [] },
  conversas_ativas: [],
  qualidade: { regras: [] },
  procuras,
};

const t = chave => chave;
const conversas = lista => lista.map(item => item.conversa);

describe('filtrarProcuras', () => {
  it('deixa os testes de fora, a não ser que peçam', () => {
    expect(conversas(filtrarProcuras(procuras, {}, catalogo))).toEqual([
      101, 102, 103,
    ]);
    expect(filtrarProcuras(procuras, { testes: true }, catalogo).length).toBe(
      4
    );
  });

  it('filtra por tema, origem, perda e pessoa', () => {
    expect(
      conversas(filtrarProcuras(procuras, { tema: 'preco' }, catalogo))
    ).toEqual([102]);
    expect(
      conversas(filtrarProcuras(procuras, { origem: 'anuncio' }, catalogo))
    ).toEqual([102]);
    expect(
      conversas(filtrarProcuras(procuras, { perda: true }, catalogo))
    ).toEqual([102]);
    expect(
      conversas(filtrarProcuras(procuras, { pessoa: true }, catalogo))
    ).toEqual([103]);
    expect(
      conversas(
        filtrarProcuras(procuras, { qualidade: 'erro_grave' }, catalogo)
      )
    ).toEqual([103]);
  });

  it('filtra o resultado por grupo inteiro ou por item', () => {
    expect(
      conversas(
        filtrarProcuras(procuras, { resultado: 'grupo:fechou' }, catalogo)
      )
    ).toEqual([101]);
    expect(
      conversas(
        filtrarProcuras(procuras, { resultado: 'item:duvida' }, catalogo)
      )
    ).toEqual([103]);
  });

  it('conta o marco quando a procura chegou a ele ou a uma etapa depois', () => {
    const soPagou = [procura(200, { marcos: ['pagou'] })];
    expect(
      filtrarProcuras(soPagou, { marco: 'recebeu' }, catalogo, etapas).length
    ).toBe(1);
    expect(
      conversas(
        filtrarProcuras(procuras, { marco: 'recebeu' }, catalogo, etapas)
      )
    ).toEqual([101, 102]);
  });

  it('filtra pelo corte no formato corte:valor', () => {
    expect(
      conversas(filtrarProcuras(procuras, { corte: 'pedido:duvida' }, catalogo))
    ).toEqual([103]);
  });

  it('busca sem diferenciar acento nem maiúscula, no resumo, no número e no tema', () => {
    expect(textoDeBusca('  PREÇO Ação ')).toBe('preco acao');
    expect(
      conversas(filtrarProcuras(procuras, { busca: 'preco' }, catalogo))
    ).toEqual([102]);
    expect(
      conversas(filtrarProcuras(procuras, { busca: 'ORCAMENTO' }, catalogo))
    ).toEqual([101]);
    expect(
      conversas(filtrarProcuras(procuras, { busca: '#103' }, catalogo))
    ).toEqual([103]);
    expect(
      filtrarProcuras(procuras, { busca: 'prazo de entrega' }, catalogo).length
    ).toBe(2);
  });
});

describe('ordenar', () => {
  const linhas = [
    { chave: 'a', n: 2, nome: 'Banana' },
    { chave: 'b', n: null, nome: 'abacaxi' },
    { chave: 'c', n: 10, nome: 'Caju' },
    { chave: 'd', n: 2, nome: 'Ameixa' },
  ];

  it('ordena números e textos nos dois sentidos, com vazio sempre no fim', () => {
    const chaves = ordem => ordenar(linhas, ordem).map(l => l.chave);
    expect(chaves({ coluna: 'n', sentido: 'asc' })).toEqual([
      'a',
      'd',
      'c',
      'b',
    ]);
    expect(chaves({ coluna: 'n', sentido: 'desc' })).toEqual([
      'c',
      'a',
      'd',
      'b',
    ]);
    expect(chaves({ coluna: 'nome', sentido: 'asc' })).toEqual([
      'b',
      'd',
      'a',
      'c',
    ]);
  });

  it('não altera a lista original', () => {
    const copia = [...linhas];
    ordenar(linhas, { coluna: 'n', sentido: 'desc' });
    expect(linhas).toEqual(copia);
  });
});

describe('paginar', () => {
  const lista = Array.from({ length: 53 }, (_, i) => i + 1);

  it('fatia a página e diz a faixa', () => {
    const pagina = paginar(lista, 3, 25);
    expect(pagina.itens).toEqual([51, 52, 53]);
    expect(pagina).toMatchObject({
      pagina: 3,
      paginas: 3,
      total: 53,
      de: 51,
      ate: 53,
    });
  });

  it('volta para a página mais próxima quando passa do fim', () => {
    expect(paginar(lista, 9, 50).pagina).toBe(2);
    expect(paginar([], 4, 25)).toMatchObject({
      pagina: 1,
      de: 0,
      ate: 0,
      itens: [],
    });
  });
});

describe('totalDoPeriodo', () => {
  it('soma cada coluna e calcula a taxa sobre a soma', () => {
    const total = totalDoPeriodo(painel.evolucao.pontos);
    expect(total).toMatchObject({
      procuras: 3,
      conversas_novas: 3,
      compra: 2,
      fecharam: 1,
      precisavam_pessoa: 1,
      taxa_pct: 50,
    });
  });

  it('sem pedido de compra, a taxa é null (nunca zero)', () => {
    expect(totalDoPeriodo([]).taxa_pct).toBeNull();
  });
});

describe('resumoDasProcuras', () => {
  it('divide quem fechou pelos pedidos de compra, como o funil', () => {
    const lista = [
      procura(1, { compra: true, resultado_id: 'pago' }),
      procura(2, { compra: true }),
      procura(3, { compra: false, resultado_id: 'duvida' }),
      procura(4, { compra: false }),
    ];
    expect(resumoDasProcuras(lista, catalogo)).toEqual({
      total: 4,
      compra: 2,
      fecharam: 1,
      pct: 50,
    });
  });

  it('procura sem o campo compra conta como compra', () => {
    expect(resumoDasProcuras([procura(1)], catalogo).compra).toBe(1);
  });
});

describe('filtros e endereço', () => {
  it('ida e volta: só o que difere do padrão vai para o endereço', () => {
    const filtros = {
      ...FILTROS_VAZIOS,
      tema: 'preco',
      perda: true,
      busca: 'prazo',
      pagina: 2,
      tamanho: 50,
    };
    const query = enderecoDosFiltros(filtros);
    expect(query).toEqual({
      tema: 'preco',
      perda: '1',
      busca: 'prazo',
      pagina: '2',
      tamanho: '50',
    });
    expect(filtrosDoEndereco(query)).toEqual(filtros);
    expect(
      enderecoDosFiltros({ ...FILTROS_VAZIOS, pagina: 1, tamanho: 25 })
    ).toEqual({});
  });

  it('a busca guarda o espaço que a pessoa está digitando', () => {
    expect(enderecoDosFiltros({ ...FILTROS_VAZIOS, busca: 'prazo ' })).toEqual({
      busca: 'prazo ',
    });
    expect(enderecoDosFiltros({ ...FILTROS_VAZIOS, busca: '   ' })).toEqual({});
  });

  it('valor estranho no endereço vira o padrão', () => {
    const filtros = filtrosDoEndereco({
      pagina: 'x',
      tamanho: '7',
      perda: 'sim',
    });
    expect(filtros).toMatchObject({ pagina: 1, tamanho: 25, perda: false });
  });

  it('valor que não existe nas opções vira "Todos"', () => {
    const opcoes = opcoesDosFiltros(painel, t);
    const validos = filtrosValidos(
      { ...FILTROS_VAZIOS, tema: 'nao_existe', origem: 'site' },
      opcoes
    );
    expect(validos).toMatchObject({ tema: '', origem: 'site' });
  });

  it('a aba Detalhe mexe só nas chaves dela e mantém aba e período', () => {
    const atual = {
      aba: 'detalhe',
      periodo: '90',
      tema: 'velho',
      tabela: 'tema',
    };
    expect(
      enderecoDaAba(atual, 'procuras', { ...FILTROS_VAZIOS, tema: 'preco' })
    ).toEqual({
      aba: 'detalhe',
      periodo: '90',
      tema: 'preco',
    });
    expect(enderecoDaAba(atual, 'regras', FILTROS_VAZIOS)).toEqual({
      aba: 'detalhe',
      periodo: '90',
      tabela: 'regras',
    });
    expect(tabelaDoEndereco({ tabela: 'nada' })).toBe('procuras');
  });

  it('keeps origem=webhook (robot from another system) when the Detail tab rewrites the address', () => {
    const atual = { aba: 'detalhe', origem: 'webhook', periodo: '30' };
    expect(enderecoDaAba(atual, 'periodo', FILTROS_VAZIOS)).toEqual({
      aba: 'detalhe',
      origem: 'webhook',
      periodo: '30',
      tabela: 'periodo',
    });
    const comFiltro = enderecoDaAba(atual, 'procuras', {
      ...FILTROS_VAZIOS,
      origem: 'site',
    });
    expect(comFiltro).toEqual({
      aba: 'detalhe',
      origem: 'webhook',
      periodo: '30',
      veio_de: 'site',
    });
    expect(filtrosDoEndereco(comFiltro).origem).toBe('site');
  });

  it('as opções usam os nomes do catálogo e o nome do negócio para "fechou"', () => {
    const opcoes = opcoesDosFiltros(painel, t);
    expect(opcoes.temas.map(o => o.label)).toEqual([
      'AGENTS.DESEMPENHO2.B.FILTROS.TODOS',
      'Prazo de entrega',
      'Preço',
    ]);
    expect(opcoes.resultados.map(g => g.label)).toEqual([
      '',
      'Fecharam',
      'AGENTS.DESEMPENHO2.B.FILTROS.GRUPO.PAROU',
      'AGENTS.DESEMPENHO2.B.FILTROS.GRUPO.RESOLVEU',
    ]);
    expect(opcoes.cortes[1].options.map(o => o.value)).toEqual([
      'pedido:comprar',
      'pedido:duvida',
    ]);
  });
});

describe('telas da aba Detalhe', () => {
  beforeEach(() => {
    router.replace.mockClear();
  });

  it('cada linha leva à conversa em outra aba, pelo número que a pessoa vê', async () => {
    rota.atual = reactive({ query: {} });
    const abrir = vi.spyOn(window, 'open').mockImplementation(() => null);
    const tela = mount(TabelaProcuras, { props: { painel } });
    await flushPromises();
    const links = tela.findAll('[data-link-conversa]');
    expect(links.map(link => link.attributes('href'))).toEqual([
      '/app/conversations/101',
      '/app/conversations/102',
      '/app/conversations/103',
    ]);
    expect(links[0].attributes('target')).toBe('_blank');
    expect(links[0].attributes('rel')).toBe('noopener noreferrer');
    await tela.find('[data-linha="102-1"]').trigger('click');
    expect(abrir).toHaveBeenCalledWith(
      '/app/conversations/102',
      '_blank',
      'noopener,noreferrer'
    );
    expect(tela.find('select').exists()).toBe(false);
    abrir.mockRestore();
  });

  it('lê os filtros do endereço e grava a mudança de volta', async () => {
    rota.atual = reactive({ query: { aba: 'detalhe', tema: 'preco' } });
    const tela = mount(TabelaProcuras, { props: { painel } });
    await flushPromises();
    expect(tela.findAll('[data-link-conversa]')).toHaveLength(1);
    await tela.find('[data-interruptor="testes"]').trigger('click');
    await flushPromises();
    expect(router.replace).toHaveBeenLastCalledWith({
      query: { aba: 'detalhe', tema: 'preco', testes: '1' },
    });
  });

  it('ordenar pelo cabeçalho troca o sentido e marca aria-sort', async () => {
    rota.atual = reactive({ query: {} });
    const tela = mount(TabelaProcuras, { props: { painel } });
    await flushPromises();
    const primeiro = () => tela.find('[data-link-conversa]').attributes('href');
    expect(primeiro()).toBe('/app/conversations/101');
    await tela.find('[data-ordenar="inicio"]').trigger('click');
    expect(primeiro()).toBe('/app/conversations/103');
    expect(
      tela
        .find('[data-ordenar="inicio"]')
        .element.closest('th')
        .getAttribute('aria-sort')
    ).toBe('ascending');
  });

  it('a tabela por período fecha com o total e marca o dia parcial', () => {
    rota.atual = reactive({ query: {} });
    const tela = mount(TabelaPorPeriodo, { props: { painel } });
    const total = tela.find('[data-total]');
    expect(total.text()).toContain('AGENTS.DESEMPENHO2.B.PERIODO.TOTAL');
    expect(total.text()).toContain('3');
    expect(tela.find('[data-nota-parcial]').exists()).toBe(true);
  });

  it('a tabela base sem linhas mostra a frase de vazio', () => {
    const tela = mount(TabelaDoPainel, {
      props: {
        colunas: [{ id: 'a', titulo: 'A' }],
        linhas: [],
        legenda: 'Tabela',
        vazio: 'Nada aqui',
      },
    });
    expect(tela.text()).toContain('Nada aqui');
  });

  it('a aba abre a tabela que está no endereço', async () => {
    rota.atual = reactive({ query: { tabela: 'periodo' } });
    const tela = mount(AbaDetalhe, { props: { painel, nome: 'Agente' } });
    await flushPromises();
    expect(tela.findComponent(TabelaPorPeriodo).exists()).toBe(true);
    await tela.find('[data-opcao="regras"]').trigger('click');
    expect(router.replace).toHaveBeenLastCalledWith({
      query: { tabela: 'regras' },
    });
  });

  it.each(['procuras', 'periodo', 'tema', 'ativas', 'regras'])(
    'desenha a tabela %s com o contrato de demonstração, sem <select>',
    async tabela => {
      rota.atual = reactive({ query: { tabela } });
      const tela = mount(AbaDetalhe, {
        props: { painel: demo, nome: 'Agente' },
      });
      await flushPromises();
      expect(tela.findAll('tbody tr').length).toBeGreaterThan(0);
      expect(tela.find('select').exists()).toBe(false);
      expect(tela.text()).not.toContain('undefined');
    }
  );

  it('na demonstração, as procuras sem teste batem com a base do período', () => {
    expect(filtrarProcuras(demo.procuras, {}, demo.catalogo)).toHaveLength(
      demo.meta.base.procuras
    );
  });
});
