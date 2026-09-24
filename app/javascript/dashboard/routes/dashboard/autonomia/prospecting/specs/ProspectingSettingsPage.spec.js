import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import ProspectingSettingsPage from '../pages/ProspectingSettingsPage.vue';

vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: { getSettings: vi.fn(), updateSettings: vi.fn() },
}));

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    getStages: vi.fn().mockResolvedValue({ data: { payload: [] } }),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// Campos que a E0 (#683) tirou da conta: são da plataforma e do superadmin.
const CAMPOS_REMOVIDOS = [
  'google_places_api_key',
  'google_maps_browser_api_key',
  'clear_google_places_api_key',
  'clear_google_maps_browser_api_key',
  'provider',
  'provider_enabled',
  'default_limit',
  'max_results_per_search',
  'daily_limit',
  'monthly_limit',
  'enrichment_enabled',
];

const payloadBase = {
  id: 1,
  cache_ttl_seconds: 3600,
  default_crm_pipeline_id: null,
  default_crm_stage_id: null,
  scoring_mode: 'profile',
  scoring_profile_id: 1,
  scoring_profiles: [{ id: 1, name: 'Padrão', default: true, weights: {} }],
  active_scoring_weights: {},
  search_score_mode: 'gbp',
  usage: { daily_used: 2, monthly_used: 5 },
};

const montar = async estado => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: { payload: { ...payloadBase, ...estado } },
  });
  AutonomiaProspectingAPI.updateSettings.mockResolvedValue({
    data: { payload: { ...payloadBase, ...estado } },
  });
  const wrapper = mount(ProspectingSettingsPage, {
    global: {
      stubs: {
        BaseSettingsHeader: true,
        ChoiceSelect: true,
        RouterLink: {
          props: ['to'],
          template:
            '<a class="link" :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('ProspectingSettingsPage', () => {
  beforeEach(() => vi.clearAllMocks());

  it('não mostra campo de chave, provider, limites nem o interruptor de enriquecimento', async () => {
    const wrapper = await montar({
      platform_google_places_configured: true,
      research_enabled: true,
      ai_credential_configured: true,
    });

    expect(wrapper.findAll('input[type="password"]')).toHaveLength(0);
    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);
    const texto = wrapper.text();
    [
      'FIELDS.GOOGLE_PLACES_API_KEY',
      'FIELDS.GOOGLE_MAPS_BROWSER_API_KEY',
      'FIELDS.MAX_RESULTS',
      'FIELDS.DEFAULT_LIMIT',
      'FIELDS.DAILY_LIMIT',
      'FIELDS.MONTHLY_LIMIT',
      'FIELDS.ENRICHMENT_ENABLED',
    ].forEach(chave => expect(texto).not.toContain(chave));
    expect(wrapper.findAll('input[type="number"]')).toHaveLength(1);
  });

  it('mostra, só leitura, chaves prontas e pesquisa liberada, sem aviso de IA', async () => {
    const wrapper = await montar({
      platform_google_places_configured: true,
      google_maps_browser_api_key: 'chave-publica',
      research_enabled: true,
      ai_credential_configured: true,
    });

    const texto = wrapper.text();
    expect(texto).toContain('PROSPECTING.SETTINGS.PLATFORM.KEYS_READY');
    expect(texto).toContain('PROSPECTING.SETTINGS.PLATFORM.RESEARCH_ENABLED');
    expect(texto).not.toContain('PLATFORM.MAP_KEY_MISSING');
    expect(texto).not.toContain('PROSPECTING.AI_CREDENTIAL.MISSING_TITLE');
  });

  it('avisa quando faltam as chaves, a pesquisa e a credencial de IA do Kanban, com o caminho para configurar', async () => {
    const wrapper = await montar({
      platform_google_places_configured: false,
      google_maps_browser_api_key: null,
      research_enabled: false,
      ai_credential_configured: false,
    });

    const texto = wrapper.text();
    expect(texto).toContain('PROSPECTING.SETTINGS.PLATFORM.KEYS_MISSING');
    expect(texto).toContain('PROSPECTING.SETTINGS.PLATFORM.RESEARCH_DISABLED');
    expect(texto).toContain('PROSPECTING.AI_CREDENTIAL.MISSING_TITLE');
    expect(texto).toContain('PROSPECTING.AI_CREDENTIAL.CONFIGURE');
    expect(JSON.parse(wrapper.find('.link').attributes('data-to'))).toEqual({
      name: 'settings_applications_integration',
      params: { integration_id: 'crm_kanban_ai' },
    });
  });

  it('não afirma chaves prontas quando a conta ainda está no provider fictício', async () => {
    const wrapper = await montar({
      platform_google_places_configured: true,
      mock_provider: true,
      research_enabled: true,
      ai_credential_configured: true,
    });

    const texto = wrapper.text();
    expect(texto).not.toContain('PROSPECTING.SETTINGS.PLATFORM.KEYS_READY');
    expect(texto).toContain('PROSPECTING.SETTINGS.PLATFORM.KEYS_MOCK');
    expect(texto).toContain('PROSPECTING.MOCK_PROVIDER.TITLE');
  });

  it('avisa que o mapa falta quando só a chave de busca está pronta', async () => {
    const wrapper = await montar({
      platform_google_places_configured: true,
      google_maps_browser_api_key: null,
      research_enabled: false,
      ai_credential_configured: true,
    });

    expect(wrapper.text()).toContain(
      'PROSPECTING.SETTINGS.PLATFORM.MAP_KEY_MISSING'
    );
  });

  it('salva sem mandar chave, provider, limites nem enrichment_enabled', async () => {
    const wrapper = await montar({
      platform_google_places_configured: true,
      research_enabled: true,
      ai_credential_configured: true,
    });

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(AutonomiaProspectingAPI.updateSettings).toHaveBeenCalledTimes(1);
    const enviado = AutonomiaProspectingAPI.updateSettings.mock.calls[0][0];
    CAMPOS_REMOVIDOS.forEach(campo =>
      expect(enviado).not.toHaveProperty(campo)
    );
    expect(enviado.cache_ttl_seconds).toBe(3600);
  });
});
