// Aba Score da configuração (#681, E5 frente C). Conta não virada vê a aba
// exatamente como antes da E5; conta virada para o Orth vê os 6 componentes
// com os pesos efetivos e a leitura da nota no modo escolhido.
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

const LEGACY_WEIGHTS = {
  website: 25,
  phone: 10,
  rating: 20,
  reviews_count: 15,
  activity: 10,
  photos: 10,
  google_rank: 5,
  query_relevance: 5,
};
const ORTH_DEFAULT = {
  website: 30,
  phone: 10,
  rating: 20,
  volume: 15,
  activity: 10,
  photos: 15,
};
const ORTH_SALES = {
  website: 50,
  phone: 10,
  rating: 10,
  volume: 10,
  activity: 10,
  photos: 10,
};
const ORTH_COMPONENTS = [
  'website',
  'phone',
  'rating',
  'volume',
  'activity',
  'photos',
];

const legacyPayload = extra => ({
  id: 1,
  cache_ttl_seconds: 3600,
  default_crm_pipeline_id: null,
  default_crm_stage_id: null,
  scoring_mode: 'profile',
  scoring_profile_id: 1,
  scoring_profiles: [
    { id: 1, name: 'Padrão', default: true, weights: LEGACY_WEIGHTS },
    {
      id: 2,
      name: 'Vendas',
      default: false,
      weights: { ...LEGACY_WEIGHTS, website: 60 },
    },
  ],
  active_scoring_weights: LEGACY_WEIGHTS,
  custom_scoring_weights: LEGACY_WEIGHTS,
  search_score_mode: 'gbp',
  search_country: 'BR',
  search_countries: ['BR', 'PT'],
  usage: { daily_used: 0, monthly_used: 0 },
  ...extra,
});

const orthPayload = extra =>
  legacyPayload({
    score_engine: 'orth',
    orth_scoring_weights: ORTH_DEFAULT,
    scoring_profiles: [
      {
        id: 1,
        name: 'Padrão',
        default: true,
        restricted: false,
        weights: LEGACY_WEIGHTS,
        orth_weights: ORTH_DEFAULT,
      },
      {
        id: 2,
        name: 'Vendas',
        default: false,
        restricted: true,
        weights: { ...LEGACY_WEIGHTS, website: 60 },
        orth_weights: ORTH_SALES,
      },
    ],
    ...extra,
  });

const mountPage = async payload => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({ data: { payload } });
  AutonomiaProspectingAPI.updateSettings.mockResolvedValue({
    data: { payload },
  });
  const wrapper = mount(ProspectingSettingsPage, {
    global: {
      stubs: { BaseSettingsHeader: true, ChoiceSelect: true, RouterLink: true },
    },
  });
  await flushPromises();
  return wrapper;
};

const choice = (wrapper, ariaLabel) =>
  wrapper
    .findAllComponents({ name: 'ChoiceSelect' })
    .find(item => item.props('ariaLabel') === ariaLabel);

const scoreTab = wrapper =>
  wrapper.findAll('button[type="button"]').at(1).element.parentElement
    .nextElementSibling.nextElementSibling;

const orthRow = (wrapper, key) =>
  wrapper.find(`[data-orth-component="${key}"]`);

describe('ProspectingSettingsPage · aba Score', () => {
  beforeEach(() => vi.clearAllMocks());

  describe('conta não virada (legacy)', () => {
    // Retrato da aba tirado antes da E5: qualquer diferença aqui é mudança
    // visível para a conta que ainda não foi virada.
    it('fica exatamente como antes da E5, com ou sem o nome do motor no payload', async () => {
      const before = await mountPage(legacyPayload());
      const withEngine = await mountPage(
        legacyPayload({ score_engine: 'legacy' })
      );

      expect(scoreTab(before).outerHTML).toMatchSnapshot();
      expect(scoreTab(withEngine).outerHTML).toBe(scoreTab(before).outerHTML);
    });

    it('fica exatamente como antes também no perfil customizado', async () => {
      const wrapper = await mountPage(
        legacyPayload({ scoring_mode: 'custom', scoring_profile_id: null })
      );

      expect(scoreTab(wrapper).outerHTML).toMatchSnapshot();
      expect(wrapper.findAll('input[type="number"]')).toHaveLength(9);
    });
  });

  describe('conta virada para o Orth', () => {
    it('mostra os 6 componentes com os pesos efetivos, sem os 8 pesos antigos', async () => {
      const wrapper = await mountPage(orthPayload());

      ORTH_COMPONENTS.forEach(key => {
        const row = orthRow(wrapper, key);
        expect(row.exists()).toBe(true);
        expect(row.text()).toContain(
          `PROSPECTING.SETTINGS.ORTH.COMPONENTS.${key}`
        );
        expect(row.text()).toContain(String(ORTH_DEFAULT[key]));
      });
      const texto = wrapper.text();
      expect(texto).not.toContain('SCORING_WEIGHTS.google_rank');
      expect(texto).not.toContain('SCORING_WEIGHTS.query_relevance');
      expect(texto).not.toContain('SCORING_WEIGHTS.reviews_count');
    });

    it('troca a frase de leitura com o modo da busca', async () => {
      const wrapper = await mountPage(orthPayload());
      expect(wrapper.text()).toContain('PROSPECTING.SETTINGS.ORTH.READING_GBP');

      choice(wrapper, 'PROSPECTING.SETTINGS.FIELDS.SEARCH_SCORE_MODE').vm.$emit(
        'update:modelValue',
        'general'
      );
      await flushPromises();

      expect(wrapper.text()).toContain(
        'PROSPECTING.SETTINGS.ORTH.READING_GENERAL'
      );
      expect(wrapper.text()).not.toContain(
        'PROSPECTING.SETTINGS.ORTH.READING_GBP'
      );
    });

    it('mostra os pesos do perfil escolhido e diz quando ele é exclusivo da conta', async () => {
      const wrapper = await mountPage(orthPayload());

      choice(wrapper, 'PROSPECTING.SETTINGS.FIELDS.SCORING_PROFILE').vm.$emit(
        'update:modelValue',
        2
      );
      await flushPromises();

      expect(orthRow(wrapper, 'website').text()).toContain('50');
      expect(wrapper.text()).toContain(
        'PROSPECTING.SETTINGS.SCORING_PROFILE_RESTRICTED'
      );
    });

    it('mostra os pesos próprios da conta convertidos quando ela usa o customizado', async () => {
      const wrapper = await mountPage(
        orthPayload({
          scoring_mode: 'custom',
          scoring_profile_id: null,
          orth_scoring_weights: ORTH_SALES,
        })
      );

      expect(orthRow(wrapper, 'website').text()).toContain('50');
      expect(wrapper.text()).toContain('PROSPECTING.SETTINGS.ORTH.CUSTOM_HINT');
    });

    // O país da busca (#677) não pode sumir com a aba nova: continua na tela,
    // no Brasil quando a conta nunca escolheu, e vai junto ao salvar a nota.
    it('mantém o país da busca no Brasil e o envia ao salvar', async () => {
      const wrapper = await mountPage(orthPayload({ search_country: null }));

      expect(
        choice(wrapper, 'PROSPECTING.SEARCH_COUNTRY.LABEL').props('modelValue')
      ).toBe('BR');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      const sent = AutonomiaProspectingAPI.updateSettings.mock.calls[0][0];
      expect(sent.search_country).toBe('BR');
      expect(sent.scoring_mode).toBe('profile');
      expect(sent.scoring_profile_id).toBe(1);
    });
  });
});
