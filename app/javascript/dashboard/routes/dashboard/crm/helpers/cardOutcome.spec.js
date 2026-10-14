import {
  cardStatusLabel,
  countsAsSale,
  outcomeLabels,
  outcomeGroup,
  outcomeStatuses,
} from './cardOutcome';

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
