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

export const presetsForScoreMode = scoreMode =>
  SEARCH_PRESETS.filter(preset => preset.scoreMode === scoreMode);

export const findPreset = presetId =>
  SEARCH_PRESETS.find(preset => preset.id === presetId);

// Filtros do formulário quando a jogada é escolhida: os dela sobre os vazios.
export const presetFilters = preset => ({
  ...defaultAdvancedLeadFilters(),
  ...preset.filters,
});

const isAbsent = value => value === undefined || value === null || value === '';

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
