// Estado compartilhado da tela de busca: refs e derivados que mais de um bloco
// lê. O estado de cada frente (local, filtros, modo) mora no pedaço dela, em
// searchSlices/; aqui ele só é juntado. As ações ficam nos composables useSearch*.
import { computed, ref } from 'vue';
import {
  activeAdvancedLeadFiltersCount,
  filterLeadsByAdvancedFilters,
} from '../utils/advancedLeadFilters';
import { mergeDisjoint } from '../utils/mergeDisjoint';
import { searchCenter } from '../utils/leadDistance';
import { sortLeads } from '../utils/sortLeads';
import { isDrawnAreaReady } from '../utils/drawnArea';
import { createSliceState, sliceFormDefaults } from './searchSlices';

const createFlags = () => ({
  isLoading: ref(true),
  isSearching: ref(false),
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
  selectedSearchId: ref(null),
  selectedLeadDetailId: ref(null),
  editingSearchConfigId: ref(null),
  deleteSearchConfirmModal: ref(null),
  deleteSearchConfirmConfig: ref({
    title: '',
    description: '',
    confirmLabel: '',
  }),
});

const createForms = settings => {
  const defaultSearchForm = () => sliceFormDefaults(settings);

  return {
    defaultSearchForm,
    form: ref(defaultSearchForm()),
    crmForm: ref({
      pipeline_id: '',
      stage_id: '',
    }),
    searchConfigForm: ref({
      crm_pipeline_id: '',
      crm_stage_id: '',
    }),
  };
};

const createLeadDerived = state => {
  const filteredLeads = computed(() =>
    filterLeadsByAdvancedFilters(state.leads.value, state.resultFilters.value)
  );
  // Centro da busca aberta, para ordenar por distância (#678).
  const openSearchCenter = computed(() =>
    searchCenter(
      state.searches.value.find(
        search => search.id === state.selectedSearchId.value
      )
    )
  );
  const sortedLeads = computed(() =>
    sortLeads(filteredLeads.value, state.sortKey.value, {
      center: openSearchCenter.value,
    })
  );

  return {
    hasResults: computed(() => state.leads.value.length > 0),
    openSearchCenter,
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
    activeFiltersCount: computed(() =>
      activeAdvancedLeadFiltersCount(state.resultFilters.value)
    ),
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
      isDrawnAreaReady(state.form.value.area_type, state.drawnArea.value) &&
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
  const base = mergeDisjoint(
    flags,
    data,
    createSliceState(),
    createForms(data.settings)
  );

  return mergeDisjoint(
    base,
    createLeadDerived(base),
    createSearchDerived(base)
  );
};
