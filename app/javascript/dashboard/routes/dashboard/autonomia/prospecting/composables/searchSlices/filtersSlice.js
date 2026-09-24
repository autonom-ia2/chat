// Frente de filtros e ordenação: filtros avançados e a ordem dos resultados.
// Nova busca zera os filtros e mantém a ordenação da busca que estava aberta.
import { ref } from 'vue';
import { defaultAdvancedLeadFilters } from '../../utils/advancedLeadFilters';

const DEFAULT_SORT_KEY = 'priority_desc';

export const filtersSlice = {
  createState: () => ({
    advancedFilters: ref(defaultAdvancedLeadFilters()),
    sortKey: ref(DEFAULT_SORT_KEY),
  }),
  reset: ({ advancedFilters }) => {
    advancedFilters.value = defaultAdvancedLeadFilters();
  },
  restore: ({ advancedFilters, sortKey }, search) => {
    advancedFilters.value = {
      ...defaultAdvancedLeadFilters(),
      ...(search?.advanced_filters || {}),
    };
    sortKey.value = search?.sort_key || DEFAULT_SORT_KEY;
  },
  toPayload: ({ advancedFilters, sortKey }) => ({
    metadata: {
      advanced_filters: advancedFilters.value,
      sort_key: sortKey.value,
    },
  }),
};
