// Jogadas prontas da busca (#677), espelho de lib/services/scoring/presets.ts
// do Orth: mesmos ids, modo e filtros base, com as chaves de filtro do c2
// (advancedLeadFilters.js). Jogada não define ordenação, como no Orth. Nome e
// frase ficam no i18n (PROSPECTING.SEARCH.PRESETS.ITEMS.<i18nKey>); a cor do
// Orth virou a escala mais próxima do design system. O backend valida o id e o
// modo em Autonomia::Prospecting::SearchPresets: mudou aqui, mude lá.
import { defaultAdvancedLeadFilters } from './advancedLeadFilters';

export const SEARCH_PRESETS = Object.freeze([
  {
    id: 'vender-site',
    scoreMode: 'gbp',
    i18nKey: 'VENDER_SITE',
    filters: { has_website: 'no' },
    icon: 'i-lucide-globe',
    iconClass: 'bg-n-ruby-3 text-n-ruby-11',
    chipClass: 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11',
  },
  {
    id: 'gestao-reviews',
    scoreMode: 'gbp',
    i18nKey: 'GESTAO_REVIEWS',
    filters: { rating_max: 4.2, reviews_min: 10 },
    icon: 'i-lucide-star',
    iconClass: 'bg-n-amber-3 text-n-amber-11',
    chipClass: 'border-n-amber-6 bg-n-amber-2 text-n-amber-11',
  },
  {
    id: 'otimizacao-gbp',
    scoreMode: 'gbp',
    i18nKey: 'OTIMIZACAO_GBP',
    filters: { has_phone: 'yes', has_website: 'yes', rating_min: 4 },
    icon: 'i-lucide-settings',
    iconClass: 'bg-n-blue-3 text-n-blue-11',
    chipClass: 'border-n-blue-6 bg-n-blue-2 text-n-blue-11',
  },
  {
    id: 'prova-social',
    scoreMode: 'general',
    i18nKey: 'PROVA_SOCIAL',
    filters: { rating_min: 4.2 },
    icon: 'i-lucide-badge-check',
    iconClass: 'bg-n-teal-3 text-n-teal-11',
    chipClass: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
  },
  {
    id: 'mercado-maduro',
    scoreMode: 'general',
    i18nKey: 'MERCADO_MADURO',
    filters: { rating_min: 4, reviews_min: 20 },
    icon: 'i-lucide-medal',
    iconClass: 'bg-n-iris-3 text-n-iris-11',
    chipClass: 'border-n-iris-6 bg-n-iris-2 text-n-iris-11',
  },
  {
    id: 'presenca-digital',
    scoreMode: 'general',
    i18nKey: 'PRESENCA_DIGITAL',
    filters: { has_website: 'yes', has_phone: 'yes' },
    icon: 'i-lucide-shield-check',
    iconClass: 'bg-n-violet-3 text-n-violet-11',
    chipClass: 'border-n-violet-6 bg-n-violet-2 text-n-violet-11',
  },
]);

const isAbsent = value => value === undefined || value === null || value === '';

// Jogada salva pela conta (#732): vem de saved_presets das configurações e
// entra no formato das prontas, com o nome dado em vez da chave do i18n. O id
// é o que a busca grava ("saved-<id>"); o servidor confere conta e modo.
export const savedPresetToPreset = saved => ({
  id: saved.preset_id,
  savedId: saved.id,
  scoreMode: saved.score_mode,
  name: saved.name,
  filters: saved.filters || {},
  icon: 'i-lucide-bookmark',
  iconClass: 'bg-n-slate-3 text-n-slate-12',
  chipClass: 'border-n-slate-6 bg-n-slate-2 text-n-slate-12',
  isSaved: true,
});

// Prontas primeiro, depois as salvas da conta, só as do modo.
export const presetsForScoreMode = (scoreMode, savedPresets = []) =>
  [...SEARCH_PRESETS, ...savedPresets].filter(
    preset => preset.scoreMode === scoreMode
  );

export const findPreset = (presetId, savedPresets = []) =>
  [...SEARCH_PRESETS, ...savedPresets].find(preset => preset.id === presetId);

// Nome da jogada: o dado pela conta ou o do catálogo.
export const presetName = (preset, t) =>
  preset.isSaved
    ? preset.name
    : t(`PROSPECTING.SEARCH.PRESETS.ITEMS.${preset.i18nKey}.NAME`);

const TAGS = 'PROSPECTING.SEARCH.SAVED_PRESETS.TAGS';

// "Sem site", "Com telefone": a etiqueta muda com a resposta.
const presenceTag = (key, value) =>
  value === 'yes' || value === 'no'
    ? { key: `${key}_${value.toUpperCase()}` }
    : null;
const yesOnlyTag = (key, value) => (value === 'yes' ? { key } : null);
// "Avaliação acima de 4": a etiqueta leva o número.
const valueTag = (key, value) =>
  isAbsent(value) ? null : { key, values: { value } };

// Resumo dos filtros em etiquetas (Orth, FILTRO-27), na ordem dos grupos da
// gaveta: dor, qualificação, visibilidade e operacional.
export const filterSummaryTags = (filters, t) =>
  [
    presenceTag('HAS_WEBSITE', filters.has_website),
    presenceTag('HAS_PHOTOS', filters.has_photos),
    valueTag('REVIEWS_MIN', filters.reviews_min),
    valueTag('RATING_MIN', filters.rating_min),
    valueTag('RATING_MAX', filters.rating_max),
    valueTag('OUTSIDE_TOP', filters.outside_top),
    valueTag('SEARCH_RANK_MAX', filters.search_rank_max),
    presenceTag('HAS_PHONE', filters.has_phone),
    yesOnlyTag('OPEN_NOW', filters.open_now),
    yesOnlyTag('HAS_OPENING_HOURS', filters.has_opening_hours),
  ]
    .filter(Boolean)
    .map(({ key, values }) =>
      values ? t(`${TAGS}.${key}`, values) : t(`${TAGS}.${key}`)
    );

// Filtros do formulário quando a jogada é escolhida: os dela sobre os vazios.
export const presetFilters = preset => ({
  ...defaultAdvancedLeadFilters(),
  ...preset.filters,
});

const asNumber = value => {
  if (typeof value === 'number') return value;
  if (typeof value !== 'string' || value.trim() === '') return Number.NaN;
  return Number(value);
};

const sameFilterValue = (current, base) => {
  if (isAbsent(current) || isAbsent(base)) {
    return isAbsent(current) && isAbsent(base);
  }

  const currentNumber = asNumber(current);
  const baseNumber = asNumber(base);
  if (!Number.isNaN(currentNumber) && !Number.isNaN(baseNumber)) {
    return currentNumber === baseNumber;
  }

  return String(current) === String(base);
};

// A jogada continua marcada enquanto os filtros forem exatamente os dela:
// cada filtro da jogada com o mesmo valor e nenhum filtro a mais. Vazio, nulo e
// ausente valem o mesmo; número digitado como texto vale o número.
export const filtersMatchPreset = (filters, preset) => {
  const keys = new Set([
    ...Object.keys(filters || {}),
    ...Object.keys(preset.filters),
  ]);

  return [...keys].every(key =>
    sameFilterValue(filters?.[key], preset.filters[key])
  );
};
