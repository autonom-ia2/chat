// Caracterização do histórico de buscas (#677): listar, abrir, configurar CRM,
// apagar e carregar mais, antes da quebra da página em componentes.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAlert } from 'dashboard/composables';
import {
  ConfirmModalStub,
  MapStub,
  bakerySearch,
  buttonWithText,
  choiceSelect,
  choose,
  confirmation,
  gymSearch,
  historyCards,
  historyMeta,
  leadNames,
  mountSearchPage,
  openResultFilters,
} from './support/searchPageHarness';

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

const thirdSearch = () =>
  bakerySearch({ id: 13, query: 'mercado', location: 'Maringá, PR' });

const configModal = wrapper =>
  wrapper
    .findAll('div.fixed.inset-0 section')
    .find(section => section.text().includes('PROSPECTING.SEARCH.SAVE_CONFIG'));

describe('ProspectingSearchPage · histórico de buscas', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  it('lista as buscas com termo, local, área, métricas, tempo e total', async () => {
    const wrapper = await mountSearchPage({
      meta: historyMeta([1, 2], { total_count: 42 }),
    });

    expect(AutonomiaProspectingAPI.getSettings).toHaveBeenCalledTimes(1);
    expect(CrmKanbanAPI.getPipelines).toHaveBeenCalledTimes(1);
    expect(AutonomiaProspectingAPI.getSearches).toHaveBeenCalledWith({
      page: 1,
      per_page: 20,
    });
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RECENT_SEARCHES');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.HISTORY_COUNT');

    const [bakery, gym] = historyCards(wrapper);
    expect(historyCards(wrapper)).toHaveLength(2);
    expect(bakery.find('h3').text()).toBe('padaria');
    expect(bakery.find('p').text()).toBe(
      'Curitiba, PR · PROSPECTING.SEARCH.RADIUS_KM_VALUE'
    );
    expect(bakery.find('span.shrink-0').text()).toBe('3');
    expect(bakery.text()).toContain('PROSPECTING.SEARCH.TIME_HOURS_AGO');
    expect(gym.find('p').text()).toBe(
      'Londrina, PR · PROSPECTING.SEARCH.AREA_VIEWPORT_SHORT'
    );
    expect(gym.find('span.shrink-0').text()).toBe('0');
    expect(gym.text()).toContain('PROSPECTING.SEARCH.TIME_DAYS_AGO');
  });

  it('sem buscas mostra o vazio, não abre nada e o mapa fica sem coordenadas', async () => {
    const wrapper = await mountSearchPage({ searches: [] });

    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.EMPTY');
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.HISTORY_COUNT');
    expect(AutonomiaProspectingAPI.getSearch).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RESULTS_TITLE');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RESULTS_EMPTY');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.MAP_NO_COORDINATES');
    expect(wrapper.findComponent(MapStub).exists()).toBe(false);
  });

  it('abre a busca mais recente ao montar e destaca ela na lista', async () => {
    const wrapper = await mountSearchPage();

    expect(AutonomiaProspectingAPI.getSearch).toHaveBeenCalledTimes(1);
    expect(AutonomiaProspectingAPI.getSearch).toHaveBeenCalledWith(11);
    expect(CrmKanbanAPI.getStages).toHaveBeenCalledWith(3);
    const [bakery, gym] = historyCards(wrapper);
    expect(bakery.classes()).toContain('border-n-brand');
    expect(gym.classes()).not.toContain('border-n-brand');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RESULTS_FOR');
    expect(leadNames(wrapper)).toEqual([
      'Padaria Sol',
      'Pão Quente',
      'Confeitaria Lua',
    ]);
  });

  it('abrir outra busca carrega os leads dela e restaura a ordem e os filtros salvos', async () => {
    const wrapper = await mountSearchPage();

    await historyCards(wrapper)[1].find('button').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.getSearch).toHaveBeenLastCalledWith(12);
    expect(historyCards(wrapper)[1].classes()).toContain('border-n-brand');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.RESULTS_EMPTY');
    expect(wrapper.text()).toContain('Londrina, PR');

    await openResultFilters(wrapper);
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.SORT').props(
        'modelValue'
      )
    ).toBe('name_asc');
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE').props(
        'modelValue'
      )
    ).toBe('yes');
  });

  it('avisa quando não consegue abrir a busca', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.getSearch.mockRejectedValueOnce(new Error('fora'));

    await historyCards(wrapper)[1].find('button').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('PROSPECTING.ERRORS.LOAD_SEARCH');
  });

  it('carrega mais buscas na página seguinte sem repetir as já listadas', async () => {
    const wrapper = await mountSearchPage({
      meta: historyMeta([1, 2], { total_count: 3, has_more: true }),
    });
    AutonomiaProspectingAPI.getSearches.mockResolvedValueOnce({
      data: {
        payload: [gymSearch(), thirdSearch()],
        meta: { page: 2, per_page: 20, total_count: 3, has_more: false },
      },
    });

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.LOAD_MORE').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.getSearches).toHaveBeenLastCalledWith({
      page: 2,
      per_page: 20,
    });
    expect(historyCards(wrapper).map(card => card.find('h3').text())).toEqual([
      'padaria',
      'academia',
      'mercado',
    ]);
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.LOAD_MORE')
    ).toBeUndefined();
  });

  it('avisa quando carregar mais falha e mantém o botão', async () => {
    const wrapper = await mountSearchPage({
      meta: historyMeta([1, 2], { has_more: true }),
    });
    AutonomiaProspectingAPI.getSearches.mockRejectedValueOnce(new Error('x'));

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.LOAD_MORE').trigger(
      'click'
    );
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('PROSPECTING.ERRORS.LOAD_SEARCHES');
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.LOAD_MORE')
    ).toBeTruthy();
  });

  it('apaga a busca aberta depois de confirmar e abre a próxima', async () => {
    const wrapper = await mountSearchPage({
      meta: historyMeta([1, 2], { total_count: 2 }),
    });
    AutonomiaProspectingAPI.deleteSearch.mockResolvedValue({});

    await historyCards(wrapper)[0]
      .find('button[title="PROSPECTING.SEARCH.DELETE_SEARCH"]')
      .trigger('click');
    await flushPromises();

    const modal = wrapper.findComponent(ConfirmModalStub);
    expect(confirmation.calls).toBe(1);
    expect(modal.props()).toMatchObject({
      title: 'PROSPECTING.SEARCH.DELETE_CONFIRM_TITLE',
      description: 'PROSPECTING.SEARCH.DELETE_CONFIRM_DESCRIPTION',
      confirmLabel: 'PROSPECTING.SEARCH.DELETE_CONFIRM_ACTION',
      cancelLabel: 'PROSPECTING.SEARCH.CANCEL',
    });
    expect(AutonomiaProspectingAPI.deleteSearch).toHaveBeenCalledWith(11);
    expect(historyCards(wrapper).map(card => card.find('h3').text())).toEqual([
      'academia',
    ]);
    expect(AutonomiaProspectingAPI.getSearch).toHaveBeenLastCalledWith(12);
    expect(historyCards(wrapper)[0].classes()).toContain('border-n-brand');
  });

  it('apagar uma busca que não está aberta não troca a busca aberta', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.deleteSearch.mockResolvedValue({});

    await historyCards(wrapper)[1]
      .find('button[title="PROSPECTING.SEARCH.DELETE_SEARCH"]')
      .trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.deleteSearch).toHaveBeenCalledWith(12);
    expect(AutonomiaProspectingAPI.getSearch).toHaveBeenCalledTimes(1);
    expect(leadNames(wrapper)).toHaveLength(3);
  });

  it('não apaga quando a confirmação é cancelada', async () => {
    const wrapper = await mountSearchPage();
    confirmation.answer = false;

    await historyCards(wrapper)[0]
      .find('button[title="PROSPECTING.SEARCH.DELETE_SEARCH"]')
      .trigger('click');
    await flushPromises();

    expect(confirmation.calls).toBe(1);
    expect(AutonomiaProspectingAPI.deleteSearch).not.toHaveBeenCalled();
    expect(historyCards(wrapper)).toHaveLength(2);
  });

  it('avisa o erro da API ao apagar e mantém a busca', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.deleteSearch.mockRejectedValue({
      response: { data: { error: 'Busca em uso' } },
    });

    await historyCards(wrapper)[0]
      .find('button[title="PROSPECTING.SEARCH.DELETE_SEARCH"]')
      .trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Busca em uso');
    expect(historyCards(wrapper)).toHaveLength(2);
  });

  it('configura funil e estágio da busca e aplica na busca aberta', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.updateSearch.mockResolvedValue({
      data: {
        payload: bakerySearch({ crm_pipeline_id: 4, crm_stage_id: 41 }),
      },
    });

    await historyCards(wrapper)[0]
      .find('button[title="PROSPECTING.SEARCH.CONFIGURE_SEARCH"]')
      .trigger('click');
    await flushPromises();

    expect(configModal(wrapper).text()).toContain('padaria');
    const pipeline = choiceSelect(
      wrapper,
      'PROSPECTING.SEARCH.FIELDS.CRM_PIPELINE'
    );
    expect(pipeline.props('modelValue')).toBe(3);
    expect(pipeline.props('options').map(option => option.value)).toEqual([
      '',
      3,
      4,
    ]);
    const stage = choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.CRM_STAGE');
    expect(stage.props('modelValue')).toBe(31);
    expect(stage.props('options').map(option => option.value)).toEqual([
      '',
      31,
      32,
    ]);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.CRM_PIPELINE', 4);
    expect(CrmKanbanAPI.getStages).toHaveBeenLastCalledWith(4);
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.CRM_STAGE').props(
        'modelValue'
      )
    ).toBe(41);

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SAVE_CONFIG').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.updateSearch).toHaveBeenCalledWith(11, {
      crm_pipeline_id: 4,
      crm_stage_id: 41,
    });
    expect(configModal(wrapper)).toBeUndefined();
    expect(CrmKanbanAPI.getStages).toHaveBeenLastCalledWith(4);
  });

  it('fecha a configuração sem salvar pelo cancelar', async () => {
    const wrapper = await mountSearchPage();

    await historyCards(wrapper)[0]
      .find('button[title="PROSPECTING.SEARCH.CONFIGURE_SEARCH"]')
      .trigger('click');
    await flushPromises();
    await buttonWithText(wrapper, 'PROSPECTING.LISTS.CANCEL').trigger('click');
    await flushPromises();

    expect(configModal(wrapper)).toBeUndefined();
    expect(AutonomiaProspectingAPI.updateSearch).not.toHaveBeenCalled();
  });

  it('avisa o erro ao salvar a configuração e mantém o modal aberto', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.updateSearch.mockRejectedValue(new Error('x'));

    await historyCards(wrapper)[0]
      .find('button[title="PROSPECTING.SEARCH.CONFIGURE_SEARCH"]')
      .trigger('click');
    await flushPromises();
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SAVE_CONFIG').trigger(
      'click'
    );
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('PROSPECTING.ERRORS.UPDATE_SEARCH');
    expect(configModal(wrapper)).toBeTruthy();
  });

  it('sem permissão de gerenciar esconde configurar e apagar', async () => {
    permission.canManage = false;
    const wrapper = await mountSearchPage();

    expect(
      wrapper
        .find('button[title="PROSPECTING.SEARCH.CONFIGURE_SEARCH"]')
        .exists()
    ).toBe(false);
    expect(
      wrapper.find('button[title="PROSPECTING.SEARCH.DELETE_SEARCH"]').exists()
    ).toBe(false);
    expect(historyCards(wrapper)).toHaveLength(2);
  });
});
