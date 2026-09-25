// Leitura do detalhe do lead: composição do score, fatores negativos e
// avaliações do Google. As que exibem texto recebem o `t` de quem chama.
export const REVIEWS_MAX = 5;

const scoreComponentLabel = (key, t) => {
  const labels = {
    rating: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.RATING'),
    reviews_count: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.REVIEWS_COUNT'),
    volume: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.VOLUME'),
    website: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.WEBSITE'),
    phone: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.PHONE'),
    activity: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.ACTIVITY'),
    photos: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.PHOTOS'),
    google_rank: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.GOOGLE_RANK'),
    query_relevance: t('PROSPECTING.SEARCH.SCORE_COMPONENTS.QUERY_RELEVANCE'),
  };

  return labels[key] || key;
};

export const negativeFactorLabel = (factor, t) => {
  const key = typeof factor === 'string' ? factor : factor?.key;
  const labels = {
    missing_website: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.MISSING_WEBSITE'),
    missing_phone: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.MISSING_PHONE'),
    low_rating: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.LOW_RATING'),
    low_reviews: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.LOW_REVIEWS'),
    missing_photos: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.MISSING_PHOTOS'),
    inactive_gbp: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.INACTIVE_GBP'),
    already_in_crm: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.ALREADY_IN_CRM'),
    recently_contacted: t(
      'PROSPECTING.SEARCH.NEGATIVE_FACTORS.RECENTLY_CONTACTED'
    ),
    old_reviews: t('PROSPECTING.SEARCH.NEGATIVE_FACTORS.OLD_REVIEWS'),
    low_rating_low_volume: t(
      'PROSPECTING.SEARCH.NEGATIVE_FACTORS.LOW_RATING_LOW_VOLUME'
    ),
  };

  return factor?.reason || labels[key] || key || '-';
};

export const scoreNumber = value => {
  const number = Number(value);
  if (!Number.isFinite(number)) return '-';

  return Number.isInteger(number) ? String(number) : number.toFixed(1);
};

export const scoreWeight = value => {
  const number = Number(value);
  if (!Number.isFinite(number)) return '-';

  const percent = number <= 1 ? number * 100 : number;
  return `${scoreNumber(percent)}%`;
};

// Chave com sublinhado é marca interna do detalhe (_mode, _total e, na nota do
// Orth, _engine e _effective_weights), não componente da nota.
const isInternalKey = key => key.startsWith('_');

export const scoreBreakdownEntries = (lead, t) => {
  const breakdown = lead?.score_breakdown || {};
  const components =
    breakdown.components && typeof breakdown.components === 'object'
      ? breakdown.components
      : breakdown;

  return Object.entries(components)
    .filter(
      ([key, value]) =>
        !isInternalKey(key) && value && typeof value === 'object'
    )
    .map(([key, value]) => ({
      key,
      label: scoreComponentLabel(key, t),
      signal: value.signal ?? value.score,
      weight: value.weight,
      weightedScore: value.weighted_score ?? value.weightedScore,
    }));
};

export const negativeFactors = lead => {
  const factors = lead?.negative_factors;
  return Array.isArray(factors) ? factors : [];
};

export const leadReviews = lead => {
  const reviews =
    lead?.reviews_snapshot || lead?.reviews || lead?.review_summary || [];

  return Array.isArray(reviews) ? reviews.slice(0, REVIEWS_MAX) : [];
};

export const reviewText = review => {
  const text = review?.text;
  if (typeof text === 'string') return text;

  return text?.text || review?.originalText?.text || review?.comment || '-';
};

export const reviewAuthor = review =>
  review?.authorAttribution?.displayName || review?.author_name || '';

export const reviewTime = review =>
  review?.relativePublishTimeDescription ||
  review?.relative_time_description ||
  '';
