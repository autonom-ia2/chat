// Dono do estado da tela de busca da Prospecção. A página chama
// useProspectingSearch() uma vez; cada bloco da tela lê o mesmo contexto com
// useProspectingSearchContext().
import { inject, onMounted, provide } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { createSearchState } from './createSearchState';
import { useSearchCrm } from './useSearchCrm';
import { useSearchForm } from './useSearchForm';
import { useSearchHistory } from './useSearchHistory';
import { useSearchLeads } from './useSearchLeads';

const PROSPECTING_SEARCH_KEY = Symbol('prospectingSearch');

export const useProspectingSearch = () => {
  const { t } = useI18n();
  const canManage = useCanManage('prospecting_manage');
  const state = createSearchState();
  const crm = useSearchCrm(state);
  const leadActions = useSearchLeads(state, { canManage });
  const history = useSearchHistory(state, {
    applyCrmTarget: crm.applyCrmTarget,
    verifyLeadsWhatsApp: leadActions.verifyLeadsWhatsApp,
  });
  const searchForm = useSearchForm(state, {
    fetchSearches: history.fetchSearches,
    selectSearchPayload: history.selectSearchPayload,
    restoreSearchViewState: history.restoreSearchViewState,
  });

  const context = {
    canManage,
    ...state,
    ...crm,
    ...leadActions,
    ...history,
    ...searchForm,
  };
  provide(PROSPECTING_SEARCH_KEY, context);

  onMounted(async () => {
    const { isLoading, searches } = state;
    isLoading.value = true;
    try {
      await searchForm.fetchSettings();
      await crm.fetchCrmPipelines();
      await history.fetchSearches({ page: 1 });
      if (searches.value.length) await history.openSearch(searches.value[0]);
    } catch {
      useAlert(t('PROSPECTING.ERRORS.LOAD_SEARCHES'));
    } finally {
      isLoading.value = false;
    }
  });

  return context;
};

export const useProspectingSearchContext = () => inject(PROSPECTING_SEARCH_KEY);
