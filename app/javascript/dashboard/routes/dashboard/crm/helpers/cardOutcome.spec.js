import {
  cardStatusLabel,
  countsAsSale,
  outcomeLabels,
  outcomeGroup,
  outcomeStatuses,
  rotuloProprio,
  avisoDoDesfecho,
} from './cardOutcome';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR';
import { ref } from 'vue';
import { useCardDesfecho } from '../components/card/useCardDesfecho';

const t = key => key;

describe('cardOutcome', () => {
  it('treats a funnel without the flag as a sale funnel', () => {
    expect(countsAsSale(undefined)).toBe(true);
    expect(countsAsSale({ counts_as_sale: true })).toBe(true);
    expect(countsAsSale({ counts_as_sale: false })).toBe(false);
  });

  it('closes a non-sale funnel as resolved/cancelled', () => {
    expect(outcomeStatuses({ counts_as_sale: true })).toEqual({
      success: 'won',
      failure: 'lost',
    });
    expect(outcomeStatuses({ counts_as_sale: false })).toEqual({
      success: 'resolved',
      failure: 'cancelled',
    });
  });

  it('prefers the funnel names and falls back to the default status name', () => {
    const pipeline = {
      counts_as_sale: false,
      metadata: { outcome_labels: { failure: 'Desistiu' } },
    };
    expect(outcomeLabels(t, pipeline)).toEqual({
      success: 'CRM_KANBAN.DRAWER.STATUS_RESOLVED',
      failure: 'Desistiu',
    });
  });

  it('never renames open or archived', () => {
    const pipeline = {
      metadata: {
        outcome_labels: { success: 'Contratado', failure: 'Desistiu' },
      },
    };
    expect(cardStatusLabel(t, 'open', pipeline)).toBe(
      'CRM_KANBAN.DRAWER.STATUS_OPEN'
    );
    expect(cardStatusLabel(t, 'archived', pipeline)).toBe(
      'CRM_KANBAN.DRAWER.STATUS_ARCHIVED'
    );
    expect(cardStatusLabel(t, 'won', pipeline)).toBe('Contratado');
  });
});

describe('outcomeGroup', () => {
  it('maps both funnel kinds to the same outcome tab (#1197)', () => {
    expect(outcomeGroup('won')).toBe('success');
    expect(outcomeGroup('resolved')).toBe('success');
    expect(outcomeGroup('lost')).toBe('failure');
    expect(outcomeGroup('cancelled')).toBe('failure');
    expect(outcomeGroup('open')).toBeNull();
    expect(outcomeGroup('archived')).toBeNull();
  });
});

// #1802 — o nome próprio do desfecho vale no aviso e no diálogo só para o
// funil de modelo da corretora. Os outros, inclusive a Cobrança e o funil de
// venda com nome próprio de conta geral, ficam com o texto de hoje.
describe('custom outcome name only for broker templates (#1802)', () => {
  const { t: traduzir } = createI18n({
    legacy: false,
    locale: 'pt_BR',
    messages: { pt_BR: ptBR },
  }).global;
  const renovacao = {
    counts_as_sale: true,
    metadata: {
      template: 'RENOVACAO',
      outcome_labels: { success: 'Renovou', failure: 'Não renovou' },
    },
  };
  const cobranca = {
    counts_as_sale: false,
    metadata: { template: 'COBRANCA', outcome_labels: { success: 'Pago' } },
  };
  const vendaGeral = {
    counts_as_sale: true,
    metadata: {
      template: 'VENDAS',
      outcome_labels: { success: 'Contratado', failure: 'Desistiu' },
    },
  };
  const antigo = {
    counts_as_sale: true,
    metadata: {
      outcome_labels: { success: 'Contratado', failure: 'Desistiu' },
    },
  };

  it('Renewal says its own names after marking', () => {
    expect(rotuloProprio('won', renovacao)).toBe('Renovou');
    expect(avisoDoDesfecho(traduzir, 'won', renovacao)).toBe(
      'Marcado: Renovou.'
    );
    expect(avisoDoDesfecho(traduzir, 'lost', renovacao)).toBe(
      'Marcado: Não renovou.'
    );
    expect(avisoDoDesfecho(traduzir, 'open', renovacao)).toBe(
      'Negócio reaberto.'
    );
  });

  it('Collections and general sale funnels keep the texts of today, byte by byte', () => {
    expect(rotuloProprio('resolved', cobranca)).toBe('');
    expect(avisoDoDesfecho(traduzir, 'resolved', cobranca)).toBe(
      'Card marcado como resolvido.'
    );
    expect(avisoDoDesfecho(traduzir, 'cancelled', cobranca)).toBe(
      'Card marcado como cancelado.'
    );
    expect(avisoDoDesfecho(traduzir, 'open', cobranca)).toBe(
      'Atendimento reaberto.'
    );
    [vendaGeral, antigo].forEach(funil => {
      expect(rotuloProprio('won', funil)).toBe('');
      expect(avisoDoDesfecho(traduzir, 'won', funil)).toBe(
        'Negócio marcado como ganho.'
      );
      expect(avisoDoDesfecho(traduzir, 'lost', funil)).toBe(
        'Negócio marcado como perdido.'
      );
      expect(avisoDoDesfecho(traduzir, 'open', funil)).toBe(
        'Negócio reaberto.'
      );
    });
  });

  it('the lose dialog uses the own name only in a broker template', () => {
    const padrao = funil =>
      useCardDesfecho({
        t: traduzir,
        card: ref({ status: 'open' }),
        funil: ref(funil),
      }).perdaPadrao.value;
    expect(padrao(renovacao)).toBe(false);
    expect(padrao(vendaGeral)).toBe(true);
    expect(padrao(antigo)).toBe(true);
    expect(padrao(cobranca)).toBe(true);
    expect(
      padrao({ counts_as_sale: true, metadata: { template: 'RENOVACAO' } })
    ).toBe(true);
  });
});
