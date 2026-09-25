// Frente de filtros e ordenação. São dois estados separados: os filtros do
// formulário de nova busca (vão no pedido) e o refino da busca aberta (filtra
// os leads já carregados). Mexer num não muda o outro.
// Nova busca zera os filtros do formulário e mantém a ordenação da busca
// aberta; reabrir uma busca restaura o refino e a ordem salvos nela.
import { ref } from 'vue';
import { defaultAdvancedLeadFilters } from '../../utils/advancedLeadFilters';
import { DEFAULT_SORT_KEY } from '../../utils/sortLeads';

export const filtersSlice = {
  createState: () => ({
    formFilters: ref(defaultAdvancedLeadFilters()),
    resultFilters: ref(defaultAdvancedLeadFilters()),
    sortKey: ref(DEFAULT_SORT_KEY),
  }),
  reset: ({ formFilters }) => {
    formFilters.value = defaultAdvancedLeadFilters();
  },
  restore: ({ resultFilters, sortKey }, search) => {
    resultFilters.value = {
      ...defaultAdvancedLeadFilters(),
      ...(search?.advanced_filters || {}),
    };
    sortKey.value = search?.sort_key || DEFAULT_SORT_KEY;
  },
  // Repetir ou editar leva os filtros e a ordem que a busca pediu.
  restoreForm: ({ formFilters, sortKey }, search) => {
    formFilters.value = {
      ...defaultAdvancedLeadFilters(),
      ...(search?.advanced_filters || {}),
    };
    sortKey.value = search?.sort_key || DEFAULT_SORT_KEY;
  },
  toPayload: ({ formFilters, sortKey }) => ({
    metadata: {
      advanced_filters: formFilters.value,
      sort_key: sortKey.value,
    },
  }),
};
