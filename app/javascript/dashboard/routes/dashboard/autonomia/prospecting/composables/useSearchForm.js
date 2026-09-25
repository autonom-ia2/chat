// Formulário de nova busca: configurações da conta, envio da busca e a troca
// entre formulário e resultados. O pedido é montado pelos pedaços de cada
// frente (searchSlices/); o local tem composable próprio (useSearchLocation).
import { useI18n } from 'vue-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { alertError } from './searchAlerts';
import { buildSearchRequest, resetSlices } from './searchSlices';

export const useSearchForm = (
  state,
  { fetchSearches, selectSearchPayload, restoreSearchViewState }
) => {
  const { t } = useI18n();
  const {
    settings,
    form,
    defaultSearchForm,
    leads,
    isSearching,
    canSearch,
    showNewSearch,
    selectedLeadDetailId,
    selectedSearch,
  } = state;

  const fetchSettings = async () => {
    try {
      const { data } = await AutonomiaProspectingAPI.getSettings();
      settings.value = data.payload || {};
      form.value.requested_limit =
        settings.value.default_limit || form.value.requested_limit;
    } catch {
      settings.value = null;
    }
  };

  const submitSearch = async () => {
    if (!canSearch.value) return;

    isSearching.value = true;
    leads.value = [];

    try {
      const { data } = await AutonomiaProspectingAPI.createSearch(
        buildSearchRequest(state)
      );

      const payload = data.payload || {};
      await fetchSearches({ page: 1 });
      await selectSearchPayload(payload);
      showNewSearch.value = false;
    } catch (e) {
      alertError(e, t('PROSPECTING.ERRORS.CREATE_SEARCH'));
    } finally {
      isSearching.value = false;
    }
  };

  const toggleNewSearch = () => {
    selectedLeadDetailId.value = null;
    const nextValue = !showNewSearch.value;
    showNewSearch.value = nextValue;

    if (nextValue) {
      form.value = defaultSearchForm();
      resetSlices(state);
      return;
    }

    if (selectedSearch.value) {
      restoreSearchViewState(selectedSearch.value);
    }
  };

  return {
    fetchSettings,
    submitSearch,
    toggleNewSearch,
  };
};
