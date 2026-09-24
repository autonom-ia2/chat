import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import ProspectingSearchPage from '../pages/ProspectingSearchPage.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));

vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => true,
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getSearches: vi.fn(),
    getSearch: vi.fn(),
  },
}));

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    getStages: vi.fn().mockResolvedValue({ data: { payload: [] } }),
  },
}));

const montar = async (settings, searches = []) => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: { payload: settings },
  });
  AutonomiaProspectingAPI.getSearches.mockResolvedValue({
    data: { payload: searches, meta: { has_more: false } },
  });
  const wrapper = mount(ProspectingSearchPage, {
    global: {
      stubs: {
        ProspectingGoogleMap: {
          props: ['apiKey'],
          template: '<div class="mapa" :data-api-key="apiKey" />',
        },
        ProspectingPriorityRing: true,
        ConfirmModal: true,
        ChoiceSelect: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const abrirNovaBusca = async wrapper => {
  const botao = wrapper
    .findAll('button')
    .find(item => item.text().includes('PROSPECTING.SEARCH.NEW_SEARCH'));
  await botao.trigger('click');
  await flushPromises();
};

describe('ProspectingSearchPage', () => {
  beforeEach(() => vi.clearAllMocks());

  it('mostra o aviso de IA quando a conta não tem credencial do Kanban', async () => {
    const wrapper = await montar({ ai_credential_configured: false });

    expect(wrapper.text()).toContain('PROSPECTING.AI_CREDENTIAL.MISSING_TITLE');
  });

  it('não mostra o aviso quando a credencial existe', async () => {
    const wrapper = await montar({ ai_credential_configured: true });

    expect(wrapper.text()).not.toContain(
      'PROSPECTING.AI_CREDENTIAL.MISSING_TITLE'
    );
  });

  it('não mostra o aviso enquanto as configurações não carregaram', async () => {
    AutonomiaProspectingAPI.getSettings.mockRejectedValue(new Error('fora'));
    AutonomiaProspectingAPI.getSearches.mockResolvedValue({
      data: { payload: [], meta: { has_more: false } },
    });
    const wrapper = mount(ProspectingSearchPage, {
      global: {
        stubs: {
          ProspectingGoogleMap: true,
          ProspectingPriorityRing: true,
          ConfirmModal: true,
          ChoiceSelect: true,
        },
      },
    });
    await flushPromises();

    expect(wrapper.text()).not.toContain(
      'PROSPECTING.AI_CREDENTIAL.MISSING_TITLE'
    );
  });

  it('passa ao mapa a chave de navegador da plataforma', async () => {
    const busca = {
      id: 7,
      query: 'padaria',
      area_config: { center: { lat: -25.4, lng: -49.2 } },
    };
    AutonomiaProspectingAPI.getSearch.mockResolvedValue({
      data: { payload: { search: busca, leads: [] } },
    });
    const wrapper = await montar(
      {
        ai_credential_configured: true,
        google_maps_browser_api_key: 'chave-publica',
        google_maps_api_key: 'campo-antigo',
      },
      [busca]
    );

    const mapas = wrapper.findAll('.mapa');
    expect(mapas.length).toBeGreaterThan(0);
    mapas.forEach(mapa =>
      expect(mapa.attributes('data-api-key')).toBe('chave-publica')
    );
  });

  it('aceita pedir até 60 resultados', async () => {
    const wrapper = await montar({ ai_credential_configured: true });
    await abrirNovaBusca(wrapper);

    const limite = wrapper.find('input[max="60"]');
    expect(limite.exists()).toBe(true);
    expect(wrapper.find('input[max="50"]').exists()).toBe(false);
  });
});
