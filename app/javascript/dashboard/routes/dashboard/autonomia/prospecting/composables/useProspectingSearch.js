// Dono do estado da tela de busca da Prospecção. A página chama
// useProspectingSearch() uma vez; cada bloco da tela lê o mesmo contexto com
// useProspectingSearchContext(). O contexto é juntado com mergeDisjoint: se dois
// composables devolverem a mesma chave, a montagem quebra em vez de o último
// sobrescrever o outro em silêncio.
import { inject, onMounted, provide } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { mergeDisjoint } from '../utils/mergeDisjoint';
import { createSearchState } from './createSearchState';
import { useSearchCrm } from './useSearchCrm';
import { useSearchForm } from './useSearchForm';
import { useSearchHistory } from './useSearchHistory';
import { useSearchLeads } from './useSearchLeads';
import { useSearchLocation } from './useSearchLocation';
import { useSearchPresets } from './useSearchPresets';
import { useSearchRepeat } from './useSearchRepeat';

const PROSPECTING_SEARCH_KEY = Symbol('prospectingSearch');

// O card, o painel e as ações do lead leem este contexto. A tela de Listas
// (#682) entrega o dela, com os leads da lista, para usar os mesmos
// componentes da busca.
export const provideProspectingLeadContext = context =>
  provide(PROSPECTING_SEARCH_KEY, context);

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

  const location = useSearchLocation(state);
  const presets = useSearchPresets(state);
  const repeat = useSearchRepeat(state, {
    applyCrmTarget: crm.applyCrmTarget,
    submitSearch: searchForm.submitSearch,
  });

  const context = mergeDisjoint(
    { canManage },
    state,
    crm,
    leadActions,
    history,
    searchForm,
    location,
    presets,
    repeat
  );
  provideProspectingLeadContext(context);

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
