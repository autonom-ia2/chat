// Detalhe da nota no painel do lead (#681). Com a conta virada para o Orth, o
// score_breakdown traz o componente volume e marcas internas com objeto
// (_effective_weights); os fatores negativos têm códigos novos. No legado a
// leitura fica como era.
import {
  negativeFactorLabel,
  scoreBreakdownEntries,
} from '../../utils/leadDetail';

const t = key => `t:${key}`;

describe('leadDetail · composição da nota', () => {
  it('lê o detalhe legado como antes', () => {
    const lead = {
      score_breakdown: {
        website: { signal: 1, weight: 25, weighted_score: 25 },
        google_rank: { signal: 0.5, weight: 5, weighted_score: 2.5 },
        _mode: 'gbp',
        _total: 27.5,
      },
    };

    expect(scoreBreakdownEntries(lead, t)).toEqual([
      {
        key: 'website',
        label: 't:PROSPECTING.SEARCH.SCORE_COMPONENTS.WEBSITE',
        signal: 1,
        weight: 25,
        weightedScore: 25,
      },
      {
        key: 'google_rank',
        label: 't:PROSPECTING.SEARCH.SCORE_COMPONENTS.GOOGLE_RANK',
        signal: 0.5,
        weight: 5,
        weightedScore: 2.5,
      },
    ]);
  });

  it('não mostra as marcas internas do Orth como componente e rotula o volume', () => {
    const lead = {
      score_breakdown: {
        volume: { signal: 0.4, weight: 15, weighted_score: 6, audit: {} },
        _engine: 'orth',
        _mode: 'gbp',
        _total: 6,
        _effective_weights: { website: 30, volume: 15 },
      },
    };

    const entries = scoreBreakdownEntries(lead, t);

    expect(entries.map(entry => entry.key)).toEqual(['volume']);
    expect(entries[0].label).toBe(
      't:PROSPECTING.SEARCH.SCORE_COMPONENTS.VOLUME'
    );
  });
});

describe('leadDetail · fatores negativos', () => {
  it.each([
    ['already_in_crm', 'ALREADY_IN_CRM'],
    ['recently_contacted', 'RECENTLY_CONTACTED'],
    ['old_reviews', 'OLD_REVIEWS'],
    ['low_rating_low_volume', 'LOW_RATING_LOW_VOLUME'],
    ['missing_website', 'MISSING_WEBSITE'],
  ])('rotula %s', (code, key) => {
    expect(negativeFactorLabel(code, t)).toBe(
      `t:PROSPECTING.SEARCH.NEGATIVE_FACTORS.${key}`
    );
  });
});
