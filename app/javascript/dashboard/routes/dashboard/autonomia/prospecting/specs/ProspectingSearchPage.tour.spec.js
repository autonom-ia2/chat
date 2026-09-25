// Tour guiado da busca (#682, ACAO-40 a 43), como o do Orth: abre sozinho na
// primeira visita de quem pode buscar, percorre modo, jogada, local, decisor,
// filtros e Buscar, e fecha sozinho com os resultados na tela. O tour só
// pré-preenche: nenhuma chamada paga sai sem o clique da pessoa.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  bakerySearch,
  buttonWithText,
  mountSearchPage,
  settingsFixture,
  sunLead,
  toggleNewSearch,
  waitLocationDebounce,
} from './support/searchPageHarness';
import { locationInput, queryInput } from './support/searchFormHelpers';
import { uiSettingsStore } from './support/uiSettingsStore';

const permission = vi.hoisted(() => ({ canManage: true }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => permission.canManage) };
});
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('./support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('./support/searchPageMocks')).crmKanbanApiMock()
);

const TOUR_KEY = 'prospecting_search_tour_seen_at';
const AUTO_FINISH_WAIT_MS = 3600;

const tour = wrapper => wrapper.find('[data-test="search-tour"]');
const tourStep = wrapper => tour(wrapper).attributes('data-step');
const tourButton = (wrapper, name) =>
  wrapper.find(`[data-test="search-tour-${name}"]`);
const next = async wrapper => {
  await tourButton(wrapper, 'next').trigger('click');
  await flushPromises();
};
const filtersDrawer = wrapper =>
  wrapper.find('aside[aria-label="PROSPECTING.SEARCH.FILTER_DRAWER.TITLE"]');

const firstVisit = async (options = {}) => {
  const { store, saved } = uiSettingsStore({});
  const wrapper = await mountSearchPage({ store, ...options });
  return { wrapper, saved };
};

const paidCalls = () => [
  AutonomiaProspectingAPI.createSearch,
  AutonomiaProspectingAPI.getLocationSuggestions,
  AutonomiaProspectingAPI.getLocationDetails,
  AutonomiaProspectingAPI.researchLead,
  AutonomiaProspectingAPI.enrichLead,
];

// Anda até o passo do local com o formulário aberto pelo tour.
const walkToWhere = async wrapper => {
  await next(wrapper); // boas-vindas -> modo
  await next(wrapper); // modo -> jogada
  await next(wrapper); // jogada -> local
};

const confirmExampleLocation = async wrapper => {
  AutonomiaProspectingAPI.getLocationSuggestions.mockResolvedValue({
    data: { payload: [{ text: 'Moema, São Paulo - SP', place_id: 'moema' }] },
  });
  AutonomiaProspectingAPI.getLocationDetails.mockResolvedValue({
    data: {
      payload: {
        label: 'Moema, São Paulo - SP',
        place_id: 'moema',
        latitude: '-23.6',
        longitude: '-46.66',
      },
    },
  });
  await tourButton(wrapper, 'suggest').trigger('click');
  await waitLocationDebounce();
  await buttonWithText(wrapper, 'Moema, São Paulo - SP').trigger('click');
  await flushPromises();
};

describe('ProspectingSearchPage · tour guiado', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('abre sozinho na primeira visita e grava a marca nas preferências do usuário', async () => {
    const { wrapper, saved } = await firstVisit();

    expect(tour(wrapper).exists()).toBe(true);
    expect(tourStep(wrapper)).toBe('WELCOME');
    expect(tour(wrapper).attributes('role')).toBe('dialog');
    expect(saved).toHaveLength(1);
    expect(saved[0][TOUR_KEY]).toEqual(expect.any(String));
    expect(Number.isNaN(Date.parse(saved[0][TOUR_KEY]))).toBe(false);
  });

  it('na segunda visita não abre sozinho', async () => {
    const { store, saved } = uiSettingsStore({});
    await mountSearchPage({ store });
    const second = await mountSearchPage({ store });

    expect(tour(second).exists()).toBe(false);
    expect(saved).toHaveLength(1);
  });

  it('quem só vê não recebe o tour nem o botão de refazer', async () => {
    permission.canManage = false;
    const { wrapper, saved } = await firstVisit();

    expect(tour(wrapper).exists()).toBe(false);
    expect(tourButton(wrapper, 'restart').exists()).toBe(false);
    expect(saved).toHaveLength(0);
  });

  it('passo do modo destaca o selo e muda o texto pelo modo de nota (GMN)', async () => {
    const { wrapper } = await firstVisit({
      settings: settingsFixture({ search_score_mode: 'gbp' }),
    });
    expect(tour(wrapper).text()).toContain(
      'PROSPECTING.TOUR.STEPS.WELCOME.BODY_GBP'
    );

    await next(wrapper);

    expect(tourStep(wrapper)).toBe('MODE');
    expect(tour(wrapper).attributes('data-target')).toBe('search-mode');
    expect(wrapper.find('[data-tour="search-mode"]').exists()).toBe(true);
    expect(tour(wrapper).text()).toContain(
      'PROSPECTING.TOUR.STEPS.MODE.TITLE_GBP'
    );
    expect(tour(wrapper).text()).toContain(
      'PROSPECTING.TOUR.STEPS.MODE.BODY_GBP'
    );
  });

  it('o texto do modo Geral é outro', async () => {
    const { wrapper } = await firstVisit({
      settings: settingsFixture({ search_score_mode: 'general' }),
    });
    expect(tour(wrapper).text()).toContain(
      'PROSPECTING.TOUR.STEPS.WELCOME.BODY_GENERAL'
    );

    await next(wrapper);

    expect(tour(wrapper).text()).toContain(
      'PROSPECTING.TOUR.STEPS.MODE.TITLE_GENERAL'
    );
    expect(tour(wrapper).text()).not.toContain('_GBP');
  });

  it('a jogada abre o formulário de nova busca e destaca as jogadas', async () => {
    const { wrapper } = await firstVisit();
    expect(wrapper.find('form').exists()).toBe(false);

    await next(wrapper);
    await next(wrapper);

    expect(tourStep(wrapper)).toBe('PRESETS');
    expect(wrapper.find('form').exists()).toBe(true);
    expect(wrapper.find('[data-tour="search-presets"]').exists()).toBe(true);
    expect(tour(wrapper).text()).toContain(
      'PROSPECTING.TOUR.STEPS.PRESETS.BODY_GENERAL'
    );
  });

  it('o local vem pré-preenchido, sem pedir sugestão ao Google, e espera a confirmação', async () => {
    const { wrapper } = await firstVisit();
    await walkToWhere(wrapper);

    expect(tourStep(wrapper)).toBe('WHERE');
    expect(queryInput(wrapper).element.value).toBe(
      'PROSPECTING.TOUR.EXAMPLE.QUERY'
    );
    expect(locationInput(wrapper).element.value).toBe(
      'PROSPECTING.TOUR.EXAMPLE.LOCATION'
    );
    expect(wrapper.find('input[type="number"][min="0.1"]').element.value).toBe(
      '3'
    );
    await waitLocationDebounce();
    expect(
      AutonomiaProspectingAPI.getLocationSuggestions
    ).not.toHaveBeenCalled();
    expect(tourButton(wrapper, 'next').attributes('disabled')).toBeDefined();
    expect(tour(wrapper).text()).toContain('PROSPECTING.TOUR.WAITING_LOCATION');

    await confirmExampleLocation(wrapper);

    expect(AutonomiaProspectingAPI.getLocationSuggestions).toHaveBeenCalledWith(
      'PROSPECTING.TOUR.EXAMPLE.LOCATION'
    );
    expect(tourButton(wrapper, 'next').attributes('disabled')).toBeUndefined();
    expect(tourStep(wrapper)).toBe('WHERE');
  });

  it('decisor, filtros abrindo e fechando, e Buscar esperando o clique', async () => {
    const { wrapper } = await firstVisit();
    await walkToWhere(wrapper);
    await confirmExampleLocation(wrapper);

    await next(wrapper);
    expect(tourStep(wrapper)).toBe('DECISION_MAKER');
    expect(wrapper.find('[data-tour="search-decision-maker"]').exists()).toBe(
      true
    );

    await next(wrapper);
    expect(tourStep(wrapper)).toBe('FILTERS');
    expect(filtersDrawer(wrapper).exists()).toBe(true);

    await next(wrapper);
    expect(tourStep(wrapper)).toBe('SUBMIT');
    expect(filtersDrawer(wrapper).exists()).toBe(false);
    expect(tour(wrapper).attributes('data-target')).toBe('search-submit');
    expect(tourButton(wrapper, 'next').exists()).toBe(false);
    expect(tour(wrapper).text()).toContain('PROSPECTING.TOUR.WAITING_RESULTS');
    expect(AutonomiaProspectingAPI.createSearch).not.toHaveBeenCalled();
  });

  it('voltar do passo de filtros fecha a gaveta', async () => {
    const { wrapper } = await firstVisit();
    await walkToWhere(wrapper);
    await confirmExampleLocation(wrapper);
    await next(wrapper);
    await next(wrapper);
    expect(filtersDrawer(wrapper).exists()).toBe(true);

    await tourButton(wrapper, 'prev').trigger('click');
    await flushPromises();

    expect(tourStep(wrapper)).toBe('DECISION_MAKER');
    expect(filtersDrawer(wrapper).exists()).toBe(false);
  });

  it('a busca só roda no clique em Buscar; com resultados mostra o último passo e fecha sozinho', async () => {
    const { wrapper } = await firstVisit();
    await walkToWhere(wrapper);
    await confirmExampleLocation(wrapper);
    await next(wrapper);
    await next(wrapper);
    await next(wrapper);
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: {
        payload: {
          search: bakerySearch({ id: 21, query: 'restaurante' }),
          leads: [sunLead()],
        },
      },
    });
    AutonomiaProspectingAPI.getSearches.mockResolvedValue({
      data: {
        payload: [bakerySearch({ id: 21, query: 'restaurante' })],
        meta: { has_more: false },
      },
    });

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledTimes(1);
    expect(tourStep(wrapper)).toBe('RESULTS');
    expect(tour(wrapper).attributes('data-target')).toBe('search-results');
    expect(wrapper.find('[data-tour="search-results"]').exists()).toBe(true);

    await new Promise(resolve => {
      setTimeout(resolve, AUTO_FINISH_WAIT_MS);
    });
    await flushPromises();

    expect(tour(wrapper).exists()).toBe(false);
  }, 10000);

  it('busca sem resultado não avança o tour', async () => {
    const { wrapper } = await firstVisit();
    await walkToWhere(wrapper);
    await confirmExampleLocation(wrapper);
    await next(wrapper);
    await next(wrapper);
    await next(wrapper);
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: bakerySearch({ id: 22 }), leads: [] } },
    });

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(tourStep(wrapper)).toBe('SUBMIT');
  });

  it('percorrer o tour até Buscar não dispara nenhuma chamada paga sozinho', async () => {
    const { wrapper } = await firstVisit();
    await walkToWhere(wrapper);
    await waitLocationDebounce();

    paidCalls().forEach(call => expect(call).not.toHaveBeenCalled());
  });

  it('pular fecha o tour e Esc também', async () => {
    const { wrapper } = await firstVisit();

    await tourButton(wrapper, 'skip').trigger('click');
    expect(tour(wrapper).exists()).toBe(false);

    await tourButton(wrapper, 'restart').trigger('click');
    await flushPromises();
    expect(tourStep(wrapper)).toBe('WELCOME');

    await tour(wrapper).trigger('keydown', { key: 'Escape' });
    expect(tour(wrapper).exists()).toBe(false);
  });

  it('Refazer tour, no rodapé, reabre o tour do começo para quem já viu', async () => {
    const wrapper = await mountSearchPage();
    expect(tour(wrapper).exists()).toBe(false);

    await tourButton(wrapper, 'restart').trigger('click');
    await flushPromises();

    expect(tourStep(wrapper)).toBe('WELCOME');
    expect(tourButton(wrapper, 'restart').text()).toBe(
      'PROSPECTING.TOUR.RESTART'
    );
  });

  it('refazer com o formulário já aberto não apaga o que a pessoa digitou antes do passo do local', async () => {
    const wrapper = await mountSearchPage({ searches: [] });
    await toggleNewSearch(wrapper);
    await queryInput(wrapper).setValue('padaria');

    await tourButton(wrapper, 'restart').trigger('click');
    await flushPromises();
    await next(wrapper);
    await next(wrapper);

    expect(tourStep(wrapper)).toBe('PRESETS');
    expect(queryInput(wrapper).element.value).toBe('padaria');
  });
});
