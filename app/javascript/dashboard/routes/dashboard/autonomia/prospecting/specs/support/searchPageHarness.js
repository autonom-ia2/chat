// Harness da caracterização da tela de busca (#677). Fixa o comportamento atual
// antes da quebra em componentes: dados de exemplo, stubs e montagem.
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ProspectingSearchPage from '../../pages/ProspectingSearchPage.vue';
import { TOUR_ALREADY_SEEN, uiSettingsStore } from './uiSettingsStore';

const HOUR_MS = 60 * 60 * 1000;
const LOCATION_DEBOUNCE_WAIT_MS = 320;

export const ChoiceSelectStub = {
  name: 'ChoiceSelect',
  props: {
    modelValue: { type: [String, Number, Boolean], default: '' },
    options: { type: Array, default: () => [] },
    ariaLabel: { type: String, default: '' },
    compact: { type: Boolean, default: false },
  },
  emits: ['update:modelValue', 'change'],
  template: '<div class="choice-select-stub" />',
};

export const MapStub = {
  name: 'ProspectingGoogleMap',
  props: {
    apiKey: { type: String, default: '' },
    center: { type: Object, default: null },
    radius: { type: Number, default: 0 },
    bounds: { type: Object, default: null },
    leads: { type: Array, default: () => [] },
    fitOnRender: { type: Boolean, default: true },
    heightClass: { type: String, default: 'h-80' },
  },
  emits: ['selectLead', 'viewportChange'],
  template: '<div class="map-stub" />',
};

// A resposta do modal de confirmação é decidida pelo teste.
export const confirmation = { answer: true, calls: 0 };

export const ConfirmModalStub = {
  name: 'ConfirmModal',
  props: ['title', 'description', 'confirmLabel', 'cancelLabel'],
  methods: {
    showConfirmation() {
      confirmation.calls += 1;
      return Promise.resolve(confirmation.answer);
    },
  },
  template: '<div class="confirm-modal-stub" />',
};

export const PIPELINES = [
  { id: 3, name: 'Vendas' },
  { id: 4, name: 'Parcerias' },
];

export const STAGES_BY_PIPELINE = {
  3: [
    { id: 31, name: 'Novo' },
    { id: 32, name: 'Contato' },
  ],
  4: [{ id: 41, name: 'Triagem' }],
};

export const settingsFixture = (extra = {}) => ({
  research_enabled: true,
  ai_credential_configured: true,
  mock_provider: false,
  platform_google_places_configured: true,
  google_maps_browser_api_key: 'chave-navegador',
  search_score_mode: 'general',
  scoring_profile_id: 9,
  default_crm_pipeline_id: 3,
  default_crm_stage_id: 31,
  // Quem abre a tela nos testes pode criar card e mexer em campanha (#682).
  can_send_to_crm: true,
  can_manage_campaigns: true,
  ...extra,
});

export const bakerySearch = (extra = {}) => ({
  id: 11,
  query: 'padaria',
  location: 'Curitiba, PR',
  area_type: 'radius',
  radius: 2000,
  area_config: { center: { lat: -25.43, lng: -49.27 } },
  results_count: 3,
  contact_count: 1,
  crm_count: 1,
  average_score: 72,
  created_at: new Date(Date.now() - 2 * HOUR_MS).toISOString(),
  crm_pipeline_id: null,
  crm_stage_id: null,
  advanced_filters: null,
  sort_key: null,
  ...extra,
});

export const gymSearch = (extra = {}) => ({
  id: 12,
  query: 'academia',
  location: 'Londrina, PR',
  area_type: 'viewport',
  radius: 0,
  area_config: {
    center: { lat: -23.3, lng: -51.15 },
    bounds: { north: -23.2, south: -23.4, east: -51.0, west: -51.3 },
  },
  results_count: 0,
  contact_count: 0,
  crm_count: 0,
  average_score: null,
  created_at: new Date(Date.now() - 3 * 24 * HOUR_MS).toISOString(),
  crm_pipeline_id: null,
  crm_stage_id: null,
  advanced_filters: { has_phone: 'yes' },
  sort_key: 'name_asc',
  ...extra,
});

const reviewsFixture = () => [
  {
    name: 'r1',
    rating: 5,
    authorAttribution: { displayName: 'Maria' },
    relativePublishTimeDescription: 'há 2 dias',
    text: { text: 'Pão ótimo' },
  },
  {
    name: 'r2',
    rating: 4,
    author_name: 'João',
    relative_time_description: 'há 1 semana',
    text: 'Bom café',
  },
  { name: 'r3', originalText: { text: 'Texto original' } },
  { name: 'r4', comment: 'Comentário antigo' },
  { name: 'r5' },
  { name: 'r6', text: 'Sexta avaliação' },
];

// Lead típico: prioridade alta, site, fone com WhatsApp verificado e contato.
export const sunLead = (extra = {}) => ({
  id: 101,
  name: 'Padaria Sol',
  address: 'Rua A, 10',
  city: 'Curitiba',
  state: 'PR',
  phone: '(41) 99999-0001',
  website: 'https://sol.com.br',
  rating: 4.7,
  reviews_count: 120,
  search_rank: 2,
  priority_position: 1,
  priority_score: 82,
  score: 70,
  latitude: -25.4,
  longitude: -49.2,
  has_photos: true,
  open_now: true,
  category: 'Padaria',
  status: 'new',
  source_label: 'Google Maps',
  provider: 'google_places',
  created_at: '2026-09-01T10:00:00Z',
  whatsapp_verification_status: 'verified',
  whatsapp_verified: true,
  contact_id: 900,
  crm_card_id: null,
  enrichment_status: null,
  human_insight: 'Bem avaliada e sem reservas online',
  score_breakdown: {
    components: {
      rating: { signal: 4.7, weight: 0.3, weighted_score: 28.2 },
      website: { score: 1, weight: 20, weightedScore: 20 },
    },
  },
  negative_factors: [{ key: 'missing_photos', points: 5 }, 'low_reviews'],
  reviews_snapshot: reviewsFixture(),
  ...extra,
});

// Sem site, sem coordenadas, fone que não é WhatsApp e card de CRM já criado.
export const hotBreadLead = (extra = {}) => ({
  id: 102,
  name: 'Pão Quente',
  address: 'Rua B, 20',
  city: 'Curitiba',
  state: 'PR',
  phone: '4133330002',
  website: null,
  rating: 3.9,
  reviews_count: 200,
  search_rank: 5,
  priority_position: 2,
  priority_score: 40,
  score: 90,
  latitude: null,
  longitude: null,
  has_photos: false,
  open_now: false,
  status: 'contacted',
  source_label: null,
  provider: 'google_places',
  created_at: '2026-09-03T10:00:00Z',
  whatsapp_verification_status: 'not_whatsapp',
  contact_id: null,
  crm_card_id: 555,
  discard_reason: 'Fechado aos domingos',
  ...extra,
});

// Sem fone, já enriquecido, prioridade baixa.
export const moonLead = (extra = {}) => ({
  id: 103,
  name: 'Confeitaria Lua',
  address: 'Rua C, 30',
  city: 'Curitiba',
  state: null,
  phone: null,
  website: 'https://lua.com.br',
  rating: 4.2,
  reviews_count: 30,
  search_rank: 9,
  priority_position: 3,
  priority_score: 20,
  score: 10,
  latitude: -25.41,
  longitude: -49.21,
  has_photos: true,
  open_now: null,
  status: 'new',
  provider: 'google_places',
  created_at: '2026-09-02T10:00:00Z',
  enrichment_status: 'completed',
  decision_name: 'Ana',
  decision_role: 'Dona',
  enrichment_summary: 'Atende eventos',
  enriched_email: 'ana@lua.com',
  enriched_instagram: '@lua',
  contact_id: null,
  crm_card_id: null,
  ...extra,
});

export const defaultPayloads = () => ({
  11: {
    search: bakerySearch(),
    leads: [sunLead(), hotBreadLead(), moonLead()],
  },
  12: { search: gymSearch(), leads: [] },
});

export const historyMeta = (searches, extra = {}) => ({
  page: 1,
  per_page: 20,
  total_count: searches.length,
  total_pages: 1,
  has_more: false,
  ...extra,
});

export const mountSearchPage = async ({
  settings = settingsFixture(),
  searches = [bakerySearch(), gymSearch()],
  meta,
  payloads = defaultPayloads(),
  // Sem dizer nada, o usuário já viu o tour (#682) e ele não abre sozinho.
  uiSettings = TOUR_ALREADY_SEEN,
  store = uiSettingsStore(uiSettings).store,
} = {}) => {
  confirmation.answer = true;
  confirmation.calls = 0;
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: { payload: settings },
  });
  AutonomiaProspectingAPI.getSearches.mockResolvedValue({
    data: { payload: searches, meta: meta || historyMeta(searches) },
  });
  AutonomiaProspectingAPI.getSearch.mockImplementation(id =>
    Promise.resolve({
      data: {
        payload: payloads[id] || {
          search: searches.find(search => search.id === id),
          leads: [],
        },
      },
    })
  );
  AutonomiaProspectingAPI.verifyLeadWhatsApp.mockResolvedValue({
    data: { payload: {} },
  });
  CrmKanbanAPI.getPipelines.mockResolvedValue({
    data: { payload: PIPELINES },
  });
  CrmKanbanAPI.getStages.mockImplementation(pipelineId =>
    Promise.resolve({
      data: { payload: STAGES_BY_PIPELINE[pipelineId] || [] },
    })
  );

  const wrapper = mount(ProspectingSearchPage, {
    global: {
      plugins: [store],
      stubs: {
        ChoiceSelect: ChoiceSelectStub,
        ProspectingGoogleMap: MapStub,
        ConfirmModal: ConfirmModalStub,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

export const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().trim() === text);

export const buttonWithTitle = (wrapper, title) =>
  wrapper.find(`button[title="${title}"]`);

export const choiceSelect = (wrapper, ariaLabel) =>
  wrapper
    .findAllComponents(ChoiceSelectStub)
    .find(choice => choice.props('ariaLabel') === ariaLabel);

export const choose = async (wrapper, ariaLabel, value) => {
  const choice = choiceSelect(wrapper, ariaLabel);
  choice.vm.$emit('update:modelValue', value);
  choice.vm.$emit('change', value);
  await flushPromises();
};

export const leadCards = wrapper =>
  wrapper
    .findAll('article')
    .filter(article =>
      article.text().includes('PROSPECTING.SEARCH.OPEN_DETAILS')
    );

export const leadCard = (wrapper, name) =>
  leadCards(wrapper).find(card => card.find('h3').text() === name);

export const leadNames = wrapper =>
  leadCards(wrapper).map(card => card.find('h3').text());

export const historyCards = wrapper =>
  wrapper
    .findAll('article')
    .filter(article =>
      article.text().includes('PROSPECTING.SEARCH.RECENT_METRICS')
    );

export const toggleNewSearch = async wrapper => {
  await wrapper.find('header button').trigger('click');
  await flushPromises();
};

export const openResultFilters = async wrapper => {
  await buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.FILTER_BUTTON').trigger(
    'click'
  );
  await flushPromises();
};

export const waitLocationDebounce = async () => {
  await new Promise(resolve => {
    setTimeout(resolve, LOCATION_DEBOUNCE_WAIT_MS);
  });
  await flushPromises();
};

export const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((ok, fail) => {
    resolve = ok;
    reject = fail;
  });
  return { promise, resolve, reject };
};

export const detailPanel = wrapper => wrapper.find('div.fixed.inset-0 aside');
