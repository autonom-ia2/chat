// Ordenação local dos leads de uma busca (#678): um campo e uma direção,
// gravados juntos na chave "<campo>_<direção>" (a mesma sort_key que a busca
// já salvava, como "priority_desc"). Os campos são os do Orth (Prioridade,
// Score, Rating, Reviews, Distância e Google) mais Data e Nome, que só o
// chat2you tem. Quem não tem o valor fica no fim nas duas direções.
import { distanceKm } from './leadDistance';

const numberOrNull = value => {
  if (value === null || value === undefined || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const negated = value => (value === null ? null : -value);

// value: o que se compara. "desc" põe o maior valor primeiro. Na prioridade a
// melhor é a 1ª posição, então o valor é a posição com sinal trocado.
// defaultDirection: a que põe o melhor primeiro ao escolher o campo; distância
// e Google começam do mais perto e da 1ª posição.
const FIELDS = {
  priority: {
    value: lead => negated(numberOrNull(lead.priority_position)),
    tieBreak: lead => numberOrNull(lead.priority_score),
    defaultDirection: 'desc',
  },
  score: { value: lead => numberOrNull(lead.score), defaultDirection: 'desc' },
  rating: {
    value: lead => numberOrNull(lead.rating),
    defaultDirection: 'desc',
  },
  reviews: {
    value: lead => numberOrNull(lead.reviews_count),
    defaultDirection: 'desc',
  },
  distance: {
    value: (lead, { center }) => distanceKm(center, lead),
    defaultDirection: 'asc',
  },
  google_rank: {
    value: lead => numberOrNull(lead.search_rank),
    defaultDirection: 'asc',
  },
  created: {
    value: lead => numberOrNull(Date.parse(lead.created_at)),
    defaultDirection: 'desc',
  },
  name: { value: lead => String(lead.name || ''), defaultDirection: 'asc' },
};

export const SORT_FIELDS = Object.keys(FIELDS);
export const DEFAULT_SORT_KEY = 'priority_desc';
const DIRECTIONS = ['asc', 'desc'];

export const defaultSortDirection = field => FIELDS[field].defaultDirection;

export const sortKeyFor = (field, direction) => `${field}_${direction}`;

export const parseSortKey = sortKey => {
  const key = String(sortKey || '');
  const separator = key.lastIndexOf('_');
  const field = key.slice(0, separator);
  const direction = key.slice(separator + 1);
  if (separator > 0 && FIELDS[field] && DIRECTIONS.includes(direction)) {
    return { field, direction };
  }
  return parseSortKey(DEFAULT_SORT_KEY);
};

const compareValues = (first, second) => {
  if (typeof first === 'string') return first.localeCompare(second);
  return first - second;
};

// Sem valor vai para o fim, qualquer que seja a direção.
const compareWithMissingLast = (first, second, sign) => {
  if (first === null && second === null) return 0;
  if (first === null) return 1;
  if (second === null) return -1;
  return sign * compareValues(first, second);
};

export const sortLeads = (leads, sortKey, context = {}) => {
  const { field, direction } = parseSortKey(sortKey);
  const { value, tieBreak } = FIELDS[field];
  const sign = direction === 'asc' ? 1 : -1;
  const keyed = leads.map(lead => ({
    lead,
    value: value(lead, context),
    tie: tieBreak ? tieBreak(lead) : null,
  }));

  return keyed
    .sort(
      (first, second) =>
        compareWithMissingLast(first.value, second.value, sign) ||
        compareWithMissingLast(first.tie, second.tie, sign)
    )
    .map(item => item.lead);
};
