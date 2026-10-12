import { TIPO_AVISO, avisarEm, etapaDoAviso } from './funilForm';

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
