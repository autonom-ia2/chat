// Sinais do card do lead como no Orth (priority-utils.tsx deriveSignals):
// ordem site, fone, fotos, posição no Google; nota só se couber; teto de 4.
// A nota lê ao contrário conforme o modo da busca (GMN x Geral).
import {
  leadPrioritySignals,
  priorityValue,
} from '../../utils/prospectingPriority';

const t = (key, params) =>
  params ? `${key.split('.').pop()} ${JSON.stringify(params)}` : key;

const signals = (lead, options = {}) =>
  leadPrioritySignals(lead, { t, ...options });

const pick = (lead, key, options) =>
  signals(lead, options).find(signal => signal.key === key);

const TONE_CARD = {
  pain: 'bg-n-ruby-2',
  opportunity: 'bg-n-amber-2',
  positive: 'bg-n-teal-2',
  neutral: 'bg-n-slate-2',
};

const toneOf = signal =>
  Object.keys(TONE_CARD).find(tone => signal.card.includes(TONE_CARD[tone]));

// Sem site, fone e posição, sobra vaga para a nota.
const bareLead = extra => ({ website: null, phone: null, ...extra });

describe('prospectingPriority · anel', () => {
  it('usa só a prioridade; sem ela não cai para o score', () => {
    expect(priorityValue({ priority_score: 82.4, score: 10 })).toBe(82);
    expect(priorityValue({ priority_score: null, score: 70 })).toBeNull();
  });
});

describe('prospectingPriority · sinais do card', () => {
  it('segue a ordem do Orth: site, fone, fotos e posição', () => {
    const lead = {
      website: 'https://sol.com.br',
      phone: '(41) 99999-0001',
      photo_count: 12,
      search_rank: 2,
      rating: 4.7,
      reviews_count: 120,
    };

    expect(signals(lead).map(signal => signal.key)).toEqual([
      'website',
      'phone',
      'photos',
      'rank',
    ]);
    expect(signals(lead).map(signal => signal.label)).toEqual([
      'PROSPECTING.SEARCH.CARD_SIGNALS.HAS_SITE',
      'PROSPECTING.SEARCH.CARD_SIGNALS.HAS_PHONE',
      'PHOTOS {"count":12}',
      'GOOGLE_RANK {"rank":2}',
    ]);
  });

  it('o site vira link e o sem site não', () => {
    expect(pick({ website: 'https://sol.com.br' }, 'website').href).toBe(
      'https://sol.com.br'
    );
    const noSite = pick(bareLead(), 'website');
    expect(noSite.href).toBeNull();
    expect(noSite.label).toBe('PROSPECTING.SEARCH.CARD_SIGNALS.NO_SITE');
    expect(toneOf(noSite)).toBe('pain');
  });

  it.each([
    [0, 'PROSPECTING.SEARCH.CARD_SIGNALS.NO_PHOTO', 'pain'],
    [3, 'PROSPECTING.SEARCH.CARD_SIGNALS.FEW_PHOTOS', 'opportunity'],
    [7, 'PHOTOS {"count":7}', 'neutral'],
    [10, 'PHOTOS {"count":10}', 'positive'],
  ])('fotos: %s fotos vira "%s" (%s)', (count, label, tone) => {
    const chip = pick(bareLead({ photo_count: count }), 'photos');
    expect(chip.label).toBe(label);
    expect(toneOf(chip)).toBe(tone);
  });

  it('sem a contagem de fotos não inventa "Sem foto"', () => {
    expect(pick(bareLead({ photo_count: null }), 'photos')).toBeUndefined();
  });

  it.each([
    // nota, tom no modo GMN, tom no modo Geral
    [4.7, 'opportunity', 'positive'],
    [4.2, 'neutral', 'neutral'],
    [3.5, 'opportunity', 'opportunity'],
    [2.5, 'pain', 'pain'],
  ])('nota %s: GMN %s, Geral %s', (rating, gbpTone, generalTone) => {
    const lead = bareLead({ rating });
    const gbp = pick(lead, 'rating', { scoreMode: 'gbp' });
    const general = pick(lead, 'rating', { scoreMode: 'general' });

    expect(gbp.label).toBe(`RATING {"value":"${rating.toFixed(1)}"}`);
    expect(toneOf(gbp)).toBe(gbpTone);
    expect(toneOf(general)).toBe(generalTone);
  });

  it('modo ausente conta como GMN, como no Orth', () => {
    expect(toneOf(pick(bareLead({ rating: 4.8 }), 'rating'))).toBe(
      'opportunity'
    );
  });

  it('com quatro sinais a nota não entra', () => {
    const lead = {
      website: 'https://sol.com.br',
      phone: '1',
      photo_count: 4,
      search_rank: 12,
      rating: 4.9,
    };
    expect(signals(lead)).toHaveLength(4);
    expect(pick(lead, 'rating')).toBeUndefined();
  });

  it('avaliações só entram se sobrar vaga depois da nota', () => {
    const roomy = bareLead({ rating: 4.1, reviews_count: 150 });
    expect(signals(roomy).map(signal => signal.key)).toEqual([
      'website',
      'phone',
      'rating',
      'reviews',
    ]);
    expect(pick(roomy, 'reviews').label).toBe('REVIEWS {"count":150}');

    const full = bareLead({ photo_count: 2, rating: 4.1, reviews_count: 150 });
    expect(pick(full, 'reviews')).toBeUndefined();
  });

  it('posição no Google tem três faixas', () => {
    expect(toneOf(pick(bareLead({ search_rank: 3 }), 'rank'))).toBe('positive');
    expect(toneOf(pick(bareLead({ search_rank: 10 }), 'rank'))).toBe('neutral');
    expect(toneOf(pick(bareLead({ search_rank: 11 }), 'rank'))).toBe(
      'opportunity'
    );
  });
});
