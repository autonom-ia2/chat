import {
  TIPO_AVISO,
  avisarEm,
  etapaDoAviso,
  payloadDoFunil,
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
    metaSync: { enabled: false, events: {}, datasetId: '', pixelId: '' },
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
