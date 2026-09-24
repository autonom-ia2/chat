// Estado compartilhado da tela de busca: refs e derivados que mais de um bloco
// lê. As ações ficam nos composables useSearch*.
import { computed, ref } from 'vue';
import {
  activeAdvancedLeadFiltersCount,
  defaultAdvancedLeadFilters,
  filterLeadsByAdvancedFilters,
} from '../utils/advancedLeadFilters';
import { sortLeads } from '../utils/sortLeads';

const createFlags = () => ({
  isLoading: ref(true),
  isSearching: ref(false),
  isSuggestingLocations: ref(false),
  convertingCrmLeadId: ref(null),
  enrichingLeadId: ref(null),
  verifyingWhatsAppLeadIds: ref([]),
  bulkAction: ref(''),
  showNewSearch: ref(false),
  showFilters: ref(false),
  deletingSearchId: ref(null),
  isLoadingMoreSearches: ref(false),
});

const createData = () => ({
  selectedLeadIds: ref([]),
  searches: ref([]),
  searchHistoryMeta: ref({
    page: 1,
    per_page: 20,
    total_count: 0,
    total_pages: 0,
    has_more: false,
  }),
  leads: ref([]),
  settings: ref(null),
  crmPipelines: ref([]),
  crmStages: ref([]),
  searchConfigStages: ref([]),
  locationSuggestions: ref([]),
  locationDetails: ref(null),
  confirmedLocation: ref(''),
  previewViewport: ref(null),
  selectedSearchId: ref(null),
  selectedLeadDetailId: ref(null),
  sortKey: ref('priority_desc'),
  editingSearchConfigId: ref(null),
  deleteSearchConfirmModal: ref(null),
  deleteSearchConfirmConfig: ref({
    title: '',
    description: '',
    confirmLabel: '',
  }),
});

const createForms = settings => {
  const defaultSearchForm = () => ({
    query: '',
    location: '',
    area_type: 'radius',
    radius_km: 1,
    requested_limit: 20,
    score_mode: settings.value?.search_score_mode || 'gbp',
    auto_expand_radius: false,
  });

  return {
    defaultSearchForm,
    form: ref(defaultSearchForm()),
    crmForm: ref({
      pipeline_id: '',
      stage_id: '',
    }),
    advancedFilters: ref(defaultAdvancedLeadFilters()),
    searchConfigForm: ref({
      crm_pipeline_id: '',
      crm_stage_id: '',
    }),
  };
};

const createLeadDerived = state => {
  const filteredLeads = computed(() =>
    filterLeadsByAdvancedFilters(state.leads.value, state.advancedFilters.value)
  );
  const sortedLeads = computed(() =>
    sortLeads(filteredLeads.value, state.sortKey.value)
  );
  const activeAdvancedFiltersCount = computed(() =>
    activeAdvancedLeadFiltersCount(state.advancedFilters.value)
  );

  return {
    hasResults: computed(() => state.leads.value.length > 0),
    filteredLeads,
    sortedLeads,
    selectedLeadDetail: computed(() =>
      state.leads.value.find(
        lead => lead.id === state.selectedLeadDetailId.value
      )
    ),
    hasSelectedLeads: computed(() => state.selectedLeadIds.value.length > 0),
    selectedLeadObjects: computed(() => {
      const ids = new Set(state.selectedLeadIds.value.map(Number));
      return sortedLeads.value.filter(lead => ids.has(Number(lead.id)));
    }),
    activeAdvancedFiltersCount,
    activeFiltersCount: computed(() => activeAdvancedFiltersCount.value),
  };
};

const createSearchDerived = state => ({
  selectedSearch: computed(() =>
    state.searches.value.find(
      search => search.id === state.selectedSearchId.value
    )
  ),
  selectedSearchConfig: computed(() =>
    state.searches.value.find(
      search => search.id === state.editingSearchConfigId.value
    )
  ),
  canLoadMoreSearches: computed(
    () =>
      state.searchHistoryMeta.value.has_more &&
      !state.isLoadingMoreSearches.value
  ),
  canCreateCrmCard: computed(() =>
    Boolean(state.crmForm.value.pipeline_id && state.crmForm.value.stage_id)
  ),
  canSearch: computed(
    () =>
      state.form.value.query.trim().length > 0 &&
      state.confirmedLocation.value.trim().length > 0 &&
      !state.isSearching.value
  ),
  selectedLocationLabel: computed(
    () => state.locationDetails.value?.label || state.confirmedLocation.value
  ),
  googleMapsApiKey: computed(
    () => state.settings.value?.google_maps_browser_api_key || ''
  ),
});

export const createSearchState = () => {
  const flags = createFlags();
  const data = createData();
  const base = { ...flags, ...data, ...createForms(data.settings) };

  return {
    ...base,
    ...createLeadDerived(base),
    ...createSearchDerived(base),
  };
};
