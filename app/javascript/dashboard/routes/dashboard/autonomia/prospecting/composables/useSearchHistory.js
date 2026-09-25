// Histórico de buscas: listar, paginar, abrir uma busca e apagar.
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { restoreSlices } from './searchSlices';

export const useSearchHistory = (
  state,
  { applyCrmTarget, verifyLeadsWhatsApp }
) => {
  const { t } = useI18n();
  const {
    searches,
    searchHistoryMeta,
    isLoadingMoreSearches,
    canLoadMoreSearches,
    leads,
    openSearchResearchProgress,
    selectedSearchId,
    selectedLeadIds,
    selectedLeadDetailId,
    isLoading,
    deletingSearchId,
    deleteSearchConfirmConfig,
    deleteSearchConfirmModal,
  } = state;

  const searchHistoryParams = page => ({
    page,
    per_page: searchHistoryMeta.value.per_page,
  });

  const normalizeSearchHistoryMeta = meta => ({
    page: Number(meta?.page || 1),
    per_page: Number(meta?.per_page || searchHistoryMeta.value.per_page || 20),
    total_count: Number(meta?.total_count || 0),
    total_pages: Number(meta?.total_pages || 0),
    has_more: Boolean(meta?.has_more),
  });

  const fetchSearches = async ({ page = 1, append = false } = {}) => {
    const { data } = await AutonomiaProspectingAPI.getSearches(
      searchHistoryParams(page)
    );
    const nextSearches = data.payload || [];

    if (append) {
      const existingIds = new Set(searches.value.map(search => search.id));
      searches.value = [
        ...searches.value,
        ...nextSearches.filter(search => !existingIds.has(search.id)),
      ];
    } else {
      searches.value = nextSearches;
    }

    searchHistoryMeta.value = normalizeSearchHistoryMeta(data.meta);
  };

  const loadMoreSearches = async () => {
    if (!canLoadMoreSearches.value) return;

    isLoadingMoreSearches.value = true;
    try {
      await fetchSearches({
        page: searchHistoryMeta.value.page + 1,
        append: true,
      });
    } catch (e) {
      alertError(e, t('PROSPECTING.ERRORS.LOAD_SEARCHES'));
    } finally {
      isLoadingMoreSearches.value = false;
    }
  };

  // O que cada frente restaura ao reabrir uma busca mora no pedaço dela.
  const restoreSearchViewState = search => {
    restoreSlices(state, search);
  };

  const selectSearchPayload = async payload => {
    leads.value = payload.leads || [];
    selectedSearchId.value = payload.id || payload.search?.id;
    selectedLeadIds.value = [];
    selectedLeadDetailId.value = null;
    const search = payload.search || payload;
    openSearchResearchProgress.value = search.research_progress || null;
    restoreSearchViewState(search);
    await applyCrmTarget(search);
    verifyLeadsWhatsApp(leads.value);
  };

  const openSearch = async search => {
    selectedSearchId.value = search.id;
    selectedLeadIds.value = [];
    selectedLeadDetailId.value = null;
    isLoading.value = true;

    try {
      const { data } = await AutonomiaProspectingAPI.getSearch(search.id);
      await selectSearchPayload(data.payload || {});
    } catch {
      useAlert(t('PROSPECTING.ERRORS.LOAD_SEARCH'));
    } finally {
      isLoading.value = false;
    }
  };

  const confirmDeleteSearch = async search => {
    deleteSearchConfirmConfig.value = {
      title: t('PROSPECTING.SEARCH.DELETE_CONFIRM_TITLE'),
      description: t('PROSPECTING.SEARCH.DELETE_CONFIRM_DESCRIPTION', {
        query: search?.query || t('PROSPECTING.SEARCH.RESULTS_TITLE'),
      }),
      confirmLabel: t('PROSPECTING.SEARCH.DELETE_CONFIRM_ACTION'),
    };

    return deleteSearchConfirmModal.value?.showConfirmation();
  };

  const deleteSearch = async search => {
    if (!search?.id || deletingSearchId.value) return;
    if (!(await confirmDeleteSearch(search))) return;

    deletingSearchId.value = search.id;
    try {
      await AutonomiaProspectingAPI.deleteSearch(search.id);
      searches.value = searches.value.filter(item => item.id !== search.id);
      searchHistoryMeta.value = {
        ...searchHistoryMeta.value,
        total_count: Math.max(searchHistoryMeta.value.total_count - 1, 0),
      };
      if (selectedSearchId.value === search.id) {
        leads.value = [];
        selectedLeadIds.value = [];
        selectedLeadDetailId.value = null;
        selectedSearchId.value = searches.value[0]?.id || null;
        if (selectedSearchId.value) await openSearch(searches.value[0]);
      }
    } catch (e) {
      alertError(e, t('PROSPECTING.ERRORS.DELETE_SEARCH'));
    } finally {
      deletingSearchId.value = null;
    }
  };

  return {
    fetchSearches,
    loadMoreSearches,
    restoreSearchViewState,
    selectSearchPayload,
    openSearch,
    deleteSearch,
  };
};
