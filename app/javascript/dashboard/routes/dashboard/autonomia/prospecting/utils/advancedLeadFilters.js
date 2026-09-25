// Filtros avançados de lead: as chaves da gaveta do Orth (FiltersDrawerV2) e o
// refino local dos leads já carregados. As regras são as do motor
// (search_runner.rb#advanced_filter_matches?); mudou lá, muda aqui.
export const RANK_SLIDER_MIN = 1;
export const RANK_SLIDER_MAX = 40;
// Lugares por busca no Google (GooglePlacesProvider::MAX_RESULTS_PER_REQUEST).
// Sem a paginação da E2, as posições vão de 1 a min(Quantidade, 20).
export const GOOGLE_RESULTS_PER_SEARCH = 20;

// Última posição que a nova busca pode trazer. Começar a faixa depois dela
// deixa a busca sempre vazia, e o motor recusa (search_runner.rb
// #validate_rank_range!). O provider fictício devolve a Quantidade inteira.
export const reachableRankLimit = ({ requestedLimit, isMockProvider }) => {
  const limit = Number(requestedLimit);
  if (!limit || limit < RANK_SLIDER_MIN) return RANK_SLIDER_MAX;

  const providerLimit = isMockProvider
    ? limit
    : Math.min(limit, GOOGLE_RESULTS_PER_SEARCH);
  return Math.min(providerLimit, RANK_SLIDER_MAX);
};

export const defaultAdvancedLeadFilters = () => ({
  has_website: '',
  has_phone: '',
  has_photos: '',
  open_now: '',
  has_opening_hours: '',
  rating_min: '',
  rating_max: '',
  reviews_min: '',
  outside_top: '',
  search_rank_max: '',
});

const isSet = value => value !== '' && value !== null && value !== undefined;

const numberOrNull = value => {
  if (!isSet(value)) return null;

  const number = Number(value);
  return Number.isNaN(number) ? null : number;
};

const booleanFilterMatches = (value, filterValue) => {
  if (!filterValue) return true;
  return filterValue === 'yes' ? Boolean(value) : !value;
};

// Aberto agora e tem horário só têm a opção "sim", como no Orth.
const onlyYesFilterMatches = (value, filterValue) =>
  filterValue !== 'yes' || value === true;

// "Acima de" descarta quem não tem nota; "abaixo de" deixa passar.
const ratingMatches = (lead, filters) => {
  const rating = numberOrNull(lead.rating);
  const ratingMin = numberOrNull(filters.rating_min);
  if (ratingMin !== null && (rating === null || rating < ratingMin)) {
    return false;
  }

  const ratingMax = numberOrNull(filters.rating_max);
  return ratingMax === null || rating === null || rating <= ratingMax;
};

// Lead sem posição não entra quando há faixa: não dá para saber onde estava.
const rankMatches = (lead, filters) => {
  const outsideTop = numberOrNull(filters.outside_top);
  const searchRankMax = numberOrNull(filters.search_rank_max);
  if (outsideTop === null && searchRankMax === null) return true;

  const rank = numberOrNull(lead.search_rank);
  if (!rank) return false;
  if (outsideTop !== null && rank <= outsideTop) return false;
  return searchRankMax === null || rank <= searchRankMax;
};

const reviewsMatch = (lead, filters) => {
  const reviewsMin = numberOrNull(filters.reviews_min);
  return reviewsMin === null || Number(lead.reviews_count || 0) >= reviewsMin;
};

const leadMatches = (lead, filters) =>
  booleanFilterMatches(lead.website, filters.has_website) &&
  booleanFilterMatches(lead.phone, filters.has_phone) &&
  booleanFilterMatches(lead.has_photos, filters.has_photos) &&
  onlyYesFilterMatches(lead.open_now, filters.open_now) &&
  onlyYesFilterMatches(lead.has_opening_hours, filters.has_opening_hours) &&
  ratingMatches(lead, filters) &&
  reviewsMatch(lead, filters) &&
  rankMatches(lead, filters);

export const filterLeadsByAdvancedFilters = (leads, filters) =>
  leads.filter(lead => leadMatches(lead, filters));

// Um filtro por controle da gaveta: a avaliação conta 1 mesmo com mínimo e
// máximo, a faixa de posição conta 1 com as duas alças.
export const advancedFilterGroupCounts = filters => ({
  pain: [filters.has_website, filters.has_photos].filter(isSet).length,
  qualification:
    Number(isSet(filters.reviews_min)) +
    Number(isSet(filters.rating_min) || isSet(filters.rating_max)),
  visibility: Number(
    isSet(filters.outside_top) || isSet(filters.search_rank_max)
  ),
  operational:
    Number(isSet(filters.has_phone)) +
    Number(filters.open_now === 'yes') +
    Number(filters.has_opening_hours === 'yes'),
});

export const activeAdvancedLeadFiltersCount = filters =>
  Object.values(advancedFilterGroupCounts(filters)).reduce(
    (total, count) => total + count,
    0
  );
