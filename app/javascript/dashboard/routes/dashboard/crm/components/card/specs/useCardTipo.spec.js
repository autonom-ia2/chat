import { ref } from 'vue';
import { useCardTipo } from '../useCardTipo';

// #1498 — o card fala do jeito do funil.
const t = (chave, valores) =>
  valores ? `${chave}:${JSON.stringify(valores)}` : chave;
const tipo = funil => useCardTipo({ t, funil: ref(funil) });

describe('useCardTipo', () => {
  it('keeps the sale words in a Sell pipeline', () => {
    const jeito = tipo({ counts_as_sale: true });
    expect(jeito.atender.value).toBe(false);
    expect(jeito.texto('NEGOCIO.TELA')).toBe('CRM_CARD.NEGOCIO.TELA');
  });

  it('uses Subject words in a Serve pipeline, falling back to the usual text', () => {
    const jeito = tipo({ counts_as_sale: false });
    expect(jeito.texto('NEGOCIO.TELA')).toBe('CRM_CARD.ASSUNTO.TELA');
    expect(jeito.texto('NEGOCIO.OBSERVACOES')).toBe(
      'CRM_CARD.NEGOCIO.OBSERVACOES'
    );
    expect(jeito.cobranca.value).toBe(false);
  });

  it('layers Collections over Subject when the template is Cobrança', () => {
    const jeito = tipo({
      counts_as_sale: false,
      metadata: { template: 'COBRANCA' },
    });
    expect(jeito.cobranca.value).toBe(true);
    expect(jeito.texto('NEGOCIO.VALOR')).toBe('CRM_CARD.COBRANCA.VALOR');
    expect(jeito.texto('NEGOCIO.URGENCIA')).toBe('CRM_CARD.ASSUNTO.URGENCIA');
    expect(jeito.texto('NEGOCIO.MOEDA.BRL')).toBe('CRM_CARD.NEGOCIO.MOEDA.BRL');
    expect(jeito.texto('ETAPA.TELA')).toBe('CRM_CARD.ETAPA.TELA');
  });

  it('ignores a Cobrança template on a Sell pipeline', () => {
    const jeito = tipo({
      counts_as_sale: true,
      metadata: { template: 'COBRANCA' },
    });
    expect(jeito.cobranca.value).toBe(false);
  });

  it('tells how long the request is open', () => {
    const jeito = tipo({ counts_as_sale: false });
    const agora = new Date('2026-10-13T12:00:00Z');
    expect(jeito.tempoAberto('2026-10-10T11:00:00Z', agora)).toBe(
      'CRM_CARD.TEMPO.DIAS:{"n":3}'
    );
    expect(jeito.tempoAberto('2026-10-13T09:30:00Z', agora)).toBe(
      'CRM_CARD.TEMPO.HORAS:{"n":2}'
    );
    expect(jeito.tempoAberto('2026-10-13T12:00:00Z', agora)).toBe(
      'CRM_CARD.TEMPO.MINUTOS:{"n":1}'
    );
  });
});
