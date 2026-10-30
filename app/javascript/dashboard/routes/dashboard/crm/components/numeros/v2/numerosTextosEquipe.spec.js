import {
  botaoDoTopoDe,
  daEquipe,
  fraseDoTopoDe,
  juntarNomes,
  tituloDoTopoDe,
} from './numerosTextosEquipe';
import { destinoDaEquipe } from './destinosEquipe';

const OUTUBRO = { dia: 19, diasNoMes: 31, fechado: false };
const P = 'CRM_NUMEROS_V2';

// #1992 (F5): os textos da visão "Equipe" e para onde cada número leva.
describe('numerosTextosEquipe', () => {
  const empresa = {
    escopo: 'empresa',
    medida: 'valor',
    feito: 13200,
    meta: 20000,
    fechadas: 18,
    frase: {
      tipo: 'empresa',
      feito: 13200,
      meta: 20000,
      resolvidos: 95,
      metaResolvidos: null,
    },
  };

  it('knows which tops belong to the team view', () => {
    expect(daEquipe(empresa)).toBe(true);
    expect(daEquipe({ escopo: 'equipe' })).toBe(true);
    expect(daEquipe({ escopo: 'eu' })).toBe(false);
    expect(daEquipe({})).toBe(false);
  });

  it('says what is left for the company goal, and the support count without a support goal', () => {
    expect(tituloDoTopoDe(empresa, OUTUBRO)).toEqual({
      key: `${P}.TOPO.FALTAM_EMPRESA`,
      params: { valor: 6800 },
    });
    expect(fraseDoTopoDe(empresa, OUTUBRO).key).toBe(
      `${P}.TOPO.FRASE.EMPRESA_RESOLVEU`
    );
  });

  it('without a goal, the team top shows the month so far', () => {
    const semMeta = { ...empresa, escopo: 'equipe', meta: null };
    expect(tituloDoTopoDe(semMeta, OUTUBRO)).toEqual({
      key: `${P}.TOPO.SEM_META_EQUIPE`,
      params: { n: 18, valor: 13200 },
      plural: 18,
    });
    expect(
      fraseDoTopoDe(
        { ...semMeta, frase: { tipo: 'equipe_vendas', ajuda: 1 } },
        OUTUBRO
      ).key
    ).toBe(`${P}.TOPO.FRASE.EQUIPE_VENDAS_SEM_META`);
  });

  it('the support team counts cases and reminders, never the time limit', () => {
    const atende = {
      escopo: 'equipe',
      medida: 'resolvidos',
      feito: 95,
      meta: null,
      frase: { tipo: 'equipe_atende', em10: null, lembretes: 7 },
    };
    expect(tituloDoTopoDe(atende, OUTUBRO)).toEqual({
      key: `${P}.TOPO.SEM_META_RESOLVEU_EQUIPE`,
      params: { n: 95 },
      plural: 95,
    });
    expect(fraseDoTopoDe(atende, OUTUBRO)).toEqual({
      key: `${P}.TOPO.FRASE.EQUIPE_ATENDE_SEM_PRAZO`,
      params: atende.frase,
      plural: 7,
    });
  });

  it('on days 1 to 3 the team top is "too early", like the personal one', () => {
    expect(tituloDoTopoDe(empresa, { ...OUTUBRO, dia: 2 }).key).toBe(
      `${P}.TOPO.CEDO`
    );
  });

  it('keeps the personal tops and buttons as they were', () => {
    const eu = { escopo: 'eu', medida: 'valor', feito: 6200, meta: null };
    expect(tituloDoTopoDe({ ...eu, fechadas: 9 }, OUTUBRO).key).toBe(
      `${P}.TOPO.SEM_META_EU`
    );
    expect(botaoDoTopoDe({ tipo: 'meus_cards' }).key).toBe(
      `${P}.TOPO.BOTAO.MEUS_CARDS`
    );
    expect(botaoDoTopoDe({ tipo: 'parados', n: 9, valor: 11400 })).toEqual({
      key: `${P}.TOPO.BOTAO.PARADOS`,
      params: { n: 9, valor: 11400 },
      plural: 9,
    });
  });

  it('joins names with "you" last', () => {
    expect(juntarNomes(['Ana', 'Carla', 'você'])).toBe('Ana, Carla e você');
    expect(juntarNomes(['Ana'])).toBe('Ana');
    expect(juntarNomes([])).toBe('');
  });
});

describe('destinoDaEquipe', () => {
  const funis = { vendas: 3, suporte: 4 };

  it('opens the team lists without "owner = me"', () => {
    expect(destinoDaEquipe('atrasados', { funis }).to).toEqual({
      name: 'crm_kanban_index',
      query: { pipeline_id: '3', follow_up_status: 'overdue' },
    });
    expect(destinoDaEquipe('parados_atende', { funis }).to.query).toEqual({
      pipeline_id: '4',
      stale_days: '7',
    });
  });

  it('"who needs help" opens that person\'s list', () => {
    const item = { pessoa: { id: 12, nome: 'Bruno' } };
    expect(destinoDaEquipe('retornos', { funis, item }).to.query).toEqual({
      pipeline_id: '3',
      owner_id: '12',
      follow_up_status: 'overdue',
    });
  });

  it('closed this month only links in the current month and when the list matches', () => {
    expect(destinoDaEquipe('fechadas', { funis, fechado: true })).toBeNull();
    expect(
      destinoDaEquipe('fechadas', { funis, item: { lista: false } })
    ).toBeNull();
    expect(
      destinoDaEquipe('fechadas', { funis, item: { lista: true } }).to.query
    ).toEqual({
      pipeline_id: '3',
      view: 'list',
      result: 'won',
      closed_in: 'this_month',
    });
  });

  it('the AI opens its agent when it is one, otherwise the agents list', () => {
    expect(
      destinoDaEquipe('agente', { funis, item: { agenteId: 5 } }).to
    ).toEqual({
      name: 'autonomia_agent_panel',
      params: { agentId: '5' },
    });
    expect(destinoDaEquipe('agente', { funis, item: {} }).to).toEqual({
      name: 'autonomia_agents_index',
    });
    expect(destinoDaEquipe('ia_esperando', { funis }).to).toEqual({
      name: 'home',
      query: { da_ia: '1', esperando_min: '30', no_funil: '1' },
    });
  });

  it('a list the person cannot open is not a link', () => {
    expect(
      destinoDaEquipe('andamento', { funis, podeAbrir: () => false })
    ).toBeNull();
  });
});

// #2075 — sem a chave de valores o servidor manda o R$ vazio (null): os textos
// da Equipe falam das vendas fechadas, sem dinheiro e sem meta.
describe('numerosTextosEquipe sem valores de venda', () => {
  const equipe = {
    escopo: 'equipe',
    medida: 'valor',
    feito: null,
    meta: null,
    fechadas: 7,
    frase: { tipo: 'equipe_vendas', feito: null, meta: null, ajuda: 2 },
  };

  it('counts the closed sales in the title and keeps the help sentence', () => {
    expect(tituloDoTopoDe(equipe, OUTUBRO)).toEqual({
      key: `${P}.TOPO.FECHOU_EQUIPE_SEM_VALOR`,
      params: { n: 7 },
      plural: 7,
    });
    expect(fraseDoTopoDe(equipe, OUTUBRO)).toMatchObject({
      key: `${P}.TOPO.FRASE.EQUIPE_VENDAS_SEM_VALOR`,
      plural: 2,
    });
  });

  it('uses the same texts early in the month, where the money sentence would be empty', () => {
    const cedo = { dia: 2, diasNoMes: 31, fechado: false };
    expect(tituloDoTopoDe(equipe, cedo).key).toBe(
      `${P}.TOPO.FECHOU_EQUIPE_SEM_VALOR`
    );
    expect(fraseDoTopoDe(equipe, cedo).key).toBe(
      `${P}.TOPO.FRASE.EQUIPE_VENDAS_SEM_VALOR`
    );
  });

  it('talks about the company sales and support without money', () => {
    const empresa = {
      ...equipe,
      escopo: 'empresa',
      frase: { tipo: 'empresa', feito: null, meta: null, resolvidos: 40 },
    };
    expect(tituloDoTopoDe(empresa, OUTUBRO).key).toBe(
      `${P}.TOPO.FECHOU_EMPRESA_SEM_VALOR`
    );
    expect(fraseDoTopoDe(empresa, OUTUBRO).key).toBe(
      `${P}.TOPO.FRASE.EMPRESA_SEM_VALOR`
    );
  });

  it('opens the stalled deals without the amount', () => {
    expect(botaoDoTopoDe({ tipo: 'parados', n: 3, valor: null }).key).toBe(
      `${P}.TOPO.BOTAO.PARADOS_SEM_VALOR`
    );
    expect(botaoDoTopoDe({ tipo: 'parados', n: 3, valor: 900 }).key).toBe(
      `${P}.TOPO.BOTAO.PARADOS`
    );
  });
});
