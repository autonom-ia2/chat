import {
  botaoDoTopo,
  formatarDinheiro,
  fraseDoTopo,
  nomeDoMes,
  pctDe,
  proximoPasso,
  tituloDoTopo,
} from './numerosTextos';
import { destino } from './destinos';

const OUTUBRO = { dia: 19, diasNoMes: 31, fechado: false };

describe('numerosTextos', () => {
  it('formats money without cents when the value is whole', () => {
    expect(formatarDinheiro(6800)).toBe('R$\u00a06.800');
    expect(formatarDinheiro(0.29)).toBe('R$\u00a00,29');
  });

  it('names the month in the account time zone', () => {
    expect(nomeDoMes('2026-10', { fuso: 'America/Sao_Paulo' })).toBe('outubro');
    expect(nomeDoMes('2026-09', { fuso: 'Pacific/Auckland' })).toBe('setembro');
  });

  it('caps the bar at 100 and is 0 without a goal', () => {
    expect(pctDe(13200, 20000)).toBe(66);
    expect(pctDe(21000, 20000)).toBe(100);
    expect(pctDe(10, null)).toBe(0);
  });

  it('shows the month so far when there is no goal (F3)', () => {
    const topo = { medida: 'valor', feito: 6200, meta: null, fechadas: 9 };
    expect(tituloDoTopo(topo, OUTUBRO)).toEqual({
      key: 'CRM_NUMEROS_V2.TOPO.SEM_META_EU',
      params: { n: 9, valor: 6200 },
      plural: 9,
    });
    expect(
      tituloDoTopo({ medida: 'resolvidos', feito: 70, meta: null }, OUTUBRO)
    ).toEqual({
      key: 'CRM_NUMEROS_V2.TOPO.SEM_META_RESOLVEU',
      params: { n: 70 },
      plural: 70,
    });
  });

  it('switches to "too early" on days 1 to 3, but not in a closed month', () => {
    const topo = { medida: 'valor', feito: 600, meta: null, fechadas: 1 };
    expect(tituloDoTopo(topo, { ...OUTUBRO, dia: 2 }).key).toBe(
      'CRM_NUMEROS_V2.TOPO.CEDO'
    );
    expect(
      tituloDoTopo(topo, { dia: 2, diasNoMes: 30, fechado: true }).key
    ).toBe('CRM_NUMEROS_V2.TOPO.SEM_META_EU');
  });

  it('on days 1 to 3, the support phrase counts cases, not money', () => {
    const atende = { medida: 'resolvidos', feito: 2, meta: null, frase: {} };
    expect(fraseDoTopo(atende, { ...OUTUBRO, dia: 2 })).toEqual({
      key: 'CRM_NUMEROS_V2.TOPO.FRASE.CEDO_RESOLVEU',
      params: { dias: 2, n: 2 },
      plural: 2,
    });
    const vende = { medida: 'valor', feito: 600, meta: null, frase: {} };
    expect(fraseDoTopo(vende, { ...OUTUBRO, dia: 2 })).toEqual({
      key: 'CRM_NUMEROS_V2.TOPO.FRASE.CEDO',
      params: { dias: 2, valor: 600 },
      plural: 2,
    });
  });

  it('keeps the goal titles ready for F4', () => {
    expect(
      tituloDoTopo({ medida: 'valor', feito: 6200, meta: 8000 }, OUTUBRO)
    ).toEqual({
      key: 'CRM_NUMEROS_V2.TOPO.FALTAM_EU',
      params: { valor: 1800 },
    });
    expect(
      tituloDoTopo({ medida: 'valor', feito: 8300, meta: 8000 }, OUTUBRO).key
    ).toBe('CRM_NUMEROS_V2.TOPO.BATIDA_EU');
  });

  it('never talks about "no prazo" while the account does not record it', () => {
    const vendeAtende = {
      medida: 'valor',
      meta: null,
      frase: { tipo: 'eu_vende_atende', resolvidos: 25, noPrazo: null },
    };
    expect(fraseDoTopo(vendeAtende, OUTUBRO)).toMatchObject({
      key: 'CRM_NUMEROS_V2.TOPO.FRASE.EU_VENDE_ATENDE_SEM_PRAZO',
      plural: 25,
    });
    const atende = {
      medida: 'resolvidos',
      meta: null,
      frase: { tipo: 'eu_atende', noPrazo: null, falta: null, dias: 12 },
    };
    expect(fraseDoTopo(atende, OUTUBRO)).toMatchObject({
      key: 'CRM_NUMEROS_V2.TOPO.FRASE.EU_ATENDE_SEM_PRAZO',
      plural: 12,
    });
  });

  it('says nobody set the seller goal yet', () => {
    const topo = {
      medida: 'valor',
      meta: null,
      frase: { tipo: 'eu_vende', feito: 6200, meta: null, dias: 12 },
    };
    expect(fraseDoTopo(topo, OUTUBRO).key).toBe(
      'CRM_NUMEROS_V2.TOPO.FRASE.EU_VENDE_SEM_META'
    );
  });

  it('builds the cascade button text from its type', () => {
    expect(botaoDoTopo({ tipo: 'meus_atrasados', n: 3 })).toEqual({
      key: 'CRM_NUMEROS_V2.TOPO.BOTAO.MEUS_ATRASADOS',
      params: { n: 3, valor: undefined },
      plural: 3,
    });
    expect(botaoDoTopo({ tipo: 'meus_casos' }).key).toBe(
      'CRM_NUMEROS_V2.TOPO.BOTAO.MEUS_CASOS'
    );
  });

  it('keeps at most 2 next steps and at most 1 yellow band', () => {
    const itens = proximoPasso([
      { tipo: 'a', aviso: true },
      { tipo: 'b', aviso: true },
      { tipo: 'c' },
    ]);
    expect(itens.map(i => [i.tipo, i.aviso])).toEqual([
      ['a', true],
      ['b', false],
    ]);
  });
});

describe('destinos', () => {
  const funis = { vendas: 1, suporte: 2 };

  it('opens my overdue returns in the Kanban, as the count does', () => {
    expect(destino('meus_atrasados', { funis })).toEqual({
      to: {
        name: 'crm_kanban_index',
        query: {
          pipeline_id: '1',
          owner_id: 'me',
          follow_up_status: 'overdue',
        },
      },
    });
  });

  it('opens this month sales in the List and gives no link in a closed month', () => {
    expect(destino('fechadas', { funis }).to.query).toEqual({
      pipeline_id: '1',
      owner_id: 'me',
      view: 'list',
      result: 'won',
      closed_in: 'this_month',
    });
    expect(destino('fechadas', { funis, fechado: true })).toBeNull();
    expect(destino('resolvidos', { funis, item: { lista: false } })).toBeNull();
  });

  it('opens the campaign + me in the Kanban', () => {
    expect(
      destino('campanha_com_voce', {
        funis,
        item: { origem: 'campaign:whatsapp:7' },
      }).to.query
    ).toMatchObject({
      owner_id: 'me',
      campaign_source_ids: 'campaign:whatsapp:7',
    });
  });

  it('gives no link to "with you now" nor "the AI handed you": the inbox has no owner filter by URL yet', () => {
    expect(destino('com_voce', { funis })).toBeNull();
    expect(destino('ia_passou', { funis })).toBeNull();
  });

  it('gives no link to a list the person cannot open', () => {
    const podeAbrir = to => to.name !== 'csat_reports';
    expect(destino('deu_certo', { funis, podeAbrir })).toBeNull();
    expect(destino('meus_casos', { funis, podeAbrir })).not.toBeNull();
  });

  it('opens the Kanban without a funnel when the person has none of that kind', () => {
    expect(
      destino('meus_casos', { funis: { vendas: 1, suporte: null } }).to
    ).toEqual({ name: 'crm_kanban_index', query: { owner_id: 'me' } });
  });
});
