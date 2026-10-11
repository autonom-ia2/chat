import {
  openWork,
  outcomeKpis,
  showsSales,
  throughputDatasets,
} from './dashboardOutcomes';

describe('dashboardOutcomes', () => {
  it('shows sales for a sale funnel and for a payload without the flag', () => {
    expect(showsSales({ counts_as_sale: true })).toBe(true);
    expect(showsSales({})).toBe(true);
    expect(showsSales(null)).toBe(true);
    expect(showsSales({ counts_as_sale: false })).toBe(false);
  });

  it('reads won and lost in a sale funnel', () => {
    const summary = { counts_as_sale: true, won_count: 2, lost_count: 1 };
    expect(outcomeKpis(summary)).toEqual([
      { key: 'WON', value: 2 },
      { key: 'LOST', value: 1 },
    ]);
  });

  it('reads resolved and cancelled in a service funnel, never won', () => {
    const summary = {
      counts_as_sale: false,
      won_count: 0,
      resolved_count: 4,
      cancelled_count: 1,
    };
    expect(outcomeKpis(summary)).toEqual([
      { key: 'RESOLVED', value: 4 },
      { key: 'CANCELLED', value: 1 },
    ]);
  });

  it('charts the outcomes of the funnel kind', () => {
    expect(
      throughputDatasets({ counts_as_sale: true }).map(set => set.key)
    ).toEqual(['won', 'lost']);
    expect(
      throughputDatasets({ counts_as_sale: false }).map(set => set.key)
    ).toEqual(['resolved', 'cancelled']);
  });

  it('counts people, conversations and cards apart', () => {
    const summary = {
      open_people_count: 1,
      open_conversations_count: 1,
      open_count: 3,
    };
    expect(openWork(summary)).toEqual([
      { key: 'PEOPLE', value: 1 },
      { key: 'CONVERSATIONS', value: 1 },
      { key: 'CARDS', value: 3 },
    ]);
    expect(openWork(null)).toEqual([
      { key: 'PEOPLE', value: 0 },
      { key: 'CONVERSATIONS', value: 0 },
      { key: 'CARDS', value: 0 },
    ]);
  });
});
