import {
  TIPO_AVISO,
  avisarEm,
  etapaDoAviso,
  moedaDoFunil,
  payloadDoFunil,
  simboloDaMoeda,
} from './funilForm';

const etapas = () => [
  { editorKey: 'a', funnel_stage_type: 'lead' },
  { editorKey: 'b', funnel_stage_type: TIPO_AVISO },
  { editorKey: 'c', funnel_stage_type: 'negotiation' },
  { editorKey: 'd', funnel_stage_type: '' },
];

describe('avisarEm', () => {
  it('moves only the "wants to buy" mark and keeps the other ad types', () => {
    const lista = etapas();
    avisarEm(lista, 'd');

    expect(lista.map(etapa => etapa.funnel_stage_type)).toEqual([
      'lead',
      '',
      'negotiation',
      TIPO_AVISO,
    ]);
    expect(etapaDoAviso(lista).editorKey).toBe('d');
  });

  it('clears only the mark when the ads should hear about the sale alone', () => {
    const lista = etapas();
    avisarEm(lista, '');

    expect(lista.map(etapa => etapa.funnel_stage_type)).toEqual([
      'lead',
      '',
      'negotiation',
      '',
    ]);
    expect(etapaDoAviso(lista)).toBeNull();
  });
});

// #1548 — a etapa nova que veio do modelo leva a posição dela no modelo; a
// etapa criada pela pessoa e a que já existe não levam.
describe('payloadDoFunil', () => {
  const form = {
    name: 'Cobrança',
    description: '',
    whenToUse: '',
    countsAsSale: false,
    outcomeLabels: { success: '', failure: '' },
    monthlyTarget: '',
    metaSync: { enabled: false, events: {}, pixelId: '' },
    googleSync: { enabled: false, events: {}, conversionNames: { won: '' } },
    stages: [
      { name: 'Boleto atrasado', color: '#2563eb', modeloPosicao: 2 },
      { name: 'Minha etapa', color: '#0891b2' },
      { id: 9, name: 'Antiga', color: '#ca8a04', modeloPosicao: 1 },
    ],
  };

  it('sends template_position only for new stages that came from the template', () => {
    const { stages } = payloadDoFunil({
      form,
      pipeline: null,
      editando: false,
      ia: false,
      modelo: 'COBRANCA',
    });

    expect(stages.map(stage => stage.template_position)).toEqual([
      2,
      undefined,
      undefined,
    ]);
  });
});

// #1876 — a meta usa a moeda do funil: o rótulo mostra o símbolo dela e salvar
// não troca a moeda por real.
describe('moeda da meta', () => {
  const pipeline = { metadata: { goals: { currency: 'USD' } } };

  it('reads the funnel currency and falls back to BRL', () => {
    expect(moedaDoFunil(pipeline)).toBe('USD');
    expect(moedaDoFunil({ metadata: {} })).toBe('BRL');
    expect(moedaDoFunil(null)).toBe('BRL');
    expect(moedaDoFunil({ metadata: { goals: { currency: 'R$' } } })).toBe(
      'BRL'
    );
  });

  it('shows the symbol of the funnel currency', () => {
    expect(simboloDaMoeda('USD', 'pt-BR')).toBe('US$');
    expect(simboloDaMoeda('BRL', 'pt-BR')).toBe('R$');
    expect(simboloDaMoeda('EUR', 'en')).toBe('€');
  });

  it('keeps the funnel currency when saving the goal', () => {
    const form = {
      name: 'Vendas',
      description: '',
      whenToUse: '',
      countsAsSale: true,
      outcomeLabels: { success: '', failure: '' },
      monthlyTarget: '500',
      metaSync: { enabled: false, events: {}, pixelId: '' },
      googleSync: { enabled: false, events: {}, conversionNames: { won: '' } },
      stages: [],
    };

    const { pipeline: payload } = payloadDoFunil({
      form,
      pipeline,
      editando: true,
      ia: false,
    });

    expect(payload.goal).toEqual({
      monthly_target_cents: 50000,
      currency: 'USD',
    });
  });
});
