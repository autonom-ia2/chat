// País da busca por conta (#677, E1 frente C): escolha agrupada por continente,
// com a lista de países que o backend aceita, e salva junto com o resto.
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

const COUNTRY_LABEL = 'PROSPECTING.SEARCH_COUNTRY.LABEL';

const payload = extra => ({
  id: 1,
  cache_ttl_seconds: 3600,
  scoring_mode: 'profile',
  scoring_profile_id: 1,
  scoring_profiles: [{ id: 1, name: 'Padrão', default: true, weights: {} }],
  active_scoring_weights: {},
  search_score_mode: 'gbp',
  search_country: 'PT',
  search_countries: ['BR', 'PT', 'US', 'MX', 'IN', 'ZZ'],
  usage: { daily_used: 0, monthly_used: 0 },
  ...extra,
});

const mountPage = async (extra = {}) => {
  AutonomiaProspectingAPI.getSettings.mockResolvedValue({
    data: { payload: payload(extra) },
  });
  AutonomiaProspectingAPI.updateSettings.mockResolvedValue({
    data: { payload: payload(extra) },
  });
  const wrapper = mount(ProspectingSettingsPage, {
    global: {
      stubs: { BaseSettingsHeader: true, ChoiceSelect: true, RouterLink: true },
    },
  });
  await flushPromises();
  return wrapper;
};

const countryChoice = wrapper =>
  wrapper
    .findAllComponents({ name: 'ChoiceSelect' })
    .find(choice => choice.props('ariaLabel') === COUNTRY_LABEL);

describe('ProspectingSettingsPage · país da busca', () => {
  beforeEach(() => vi.clearAllMocks());

  it('agrupa por continente, em ordem do nome, só os países que o backend aceita', async () => {
    const wrapper = await mountPage();

    const groups = countryChoice(wrapper).props('groups');
    expect(
      groups.map(group => [
        group.label,
        group.options.map(option => option.value),
      ])
    ).toEqual([
      ['PROSPECTING.SEARCH_COUNTRY.GROUPS.SOUTH_AMERICA', ['BR']],
      ['PROSPECTING.SEARCH_COUNTRY.GROUPS.NORTH_AMERICA', ['MX', 'US']],
      ['PROSPECTING.SEARCH_COUNTRY.GROUPS.EUROPE', ['PT']],
      ['PROSPECTING.SEARCH_COUNTRY.GROUPS.ASIA', ['IN']],
      ['PROSPECTING.SEARCH_COUNTRY.GROUPS.OTHER', ['ZZ']],
    ]);
    expect(groups[0].options[0].label).toBe(
      'PROSPECTING.SEARCH_COUNTRY.COUNTRIES.BR'
    );
  });

  it('mostra o país salvo e envia o escolhido ao salvar', async () => {
    const wrapper = await mountPage();
    const choice = countryChoice(wrapper);
    expect(choice.props('modelValue')).toBe('PT');

    choice.vm.$emit('update:modelValue', 'MX');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(
      AutonomiaProspectingAPI.updateSettings.mock.calls[0][0].search_country
    ).toBe('MX');
  });

  it('usa o Brasil quando a conta nunca escolheu', async () => {
    const wrapper = await mountPage({ search_country: null });

    expect(countryChoice(wrapper).props('modelValue')).toBe('BR');
  });
});
