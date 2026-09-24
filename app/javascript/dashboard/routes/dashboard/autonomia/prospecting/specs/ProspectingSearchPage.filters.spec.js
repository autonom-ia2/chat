// Gaveta de filtros (#677, frente B): os 4 grupos do Orth, com rascunho e
// Aplicar. O filtro do formulário de nova busca e o refino da busca aberta
// são estados separados.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  bakerySearch,
  buttonWithTitle,
  choiceSelect,
  choose,
  leadNames,
  mountSearchPage,
  openResultFilters,
  sunLead,
  toggleNewSearch,
} from './support/searchPageHarness';
import {
  openNewSearchForm,
  submitMinimalSearch,
} from './support/searchFormHelpers';
import {
  DRAWER,
  applyFilters,
  checkYesOnly,
  clickPanelButton,
  filtersPanel,
  openFormFilters,
  rankInput,
} from './support/filtersHelpers';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => true) };
});
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('./support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('./support/searchPageMocks')).crmKanbanApiMock()
);

const filterBadge = wrapper =>
  buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.FILTER_BUTTON').text();

describe('ProspectingSearchPage · gaveta de filtros', () => {
  it('mostra os 4 grupos do Orth', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    const text = filtersPanel(wrapper).text();
    ['PAIN', 'QUALIFICATION', 'VISIBILITY', 'OPERATIONAL'].forEach(group => {
      expect(text).toContain(`${DRAWER}.GROUPS.${group}.TITLE`);
    });
  });

  it('no refino dos resultados, escolher só mexe no rascunho; Aplicar filtra', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no');
    expect(leadNames(wrapper)).toEqual([
      'Padaria Sol',
      'Pão Quente',
      'Confeitaria Lua',
    ]);

    await applyFilters(wrapper);
    expect(leadNames(wrapper)).toEqual(['Pão Quente']);
    expect(filterBadge(wrapper)).toBe('1');
  });

  it('Limpar tudo aplica os filtros vazios na hora', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE', 'yes');
    await applyFilters(wrapper);
    expect(leadNames(wrapper)).toEqual(['Padaria Sol', 'Pão Quente']);

    await openResultFilters(wrapper);
    await clickPanelButton(wrapper, 'CLEAR_ALL');

    expect(leadNames(wrapper)).toHaveLength(3);
    expect(filterBadge(wrapper)).toBe('');
  });

  it('avaliação com operador: escolher o operador sem estrelas não filtra', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, `${DRAWER}.RATING.OPERATOR`, 'below');
    await applyFilters(wrapper);
    expect(leadNames(wrapper)).toHaveLength(3);
    expect(filterBadge(wrapper)).toBe('');

    await openResultFilters(wrapper);
    await choose(wrapper, `${DRAWER}.RATING.OPERATOR`, 'below');
    await choose(wrapper, `${DRAWER}.RATING.VALUE`, 4);
    await applyFilters(wrapper);
    expect(leadNames(wrapper)).toEqual(['Pão Quente']);
  });

  it('trocar o operador leva as estrelas para o outro lado', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await choose(wrapper, `${DRAWER}.RATING.OPERATOR`, 'below');
    await choose(wrapper, `${DRAWER}.RATING.VALUE`, 4.5);
    await choose(wrapper, `${DRAWER}.RATING.OPERATOR`, 'above');
    await applyFilters(wrapper);

    expect(leadNames(wrapper)).toEqual(['Padaria Sol']);
  });

  it('faixa de posição de 1 a 40 com duas alças', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    expect(rankInput(wrapper, 'MIN_ARIA').attributes('min')).toBe('1');
    expect(rankInput(wrapper, 'MAX_ARIA').attributes('max')).toBe('40');
    await rankInput(wrapper, 'MIN_ARIA').setValue('3');
    await rankInput(wrapper, 'MAX_ARIA').setValue('9');
    await applyFilters(wrapper);

    expect(leadNames(wrapper)).toEqual(['Pão Quente', 'Confeitaria Lua']);
  });

  it('as alças não se cruzam', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);

    await rankInput(wrapper, 'MAX_ARIA').setValue('5');
    await rankInput(wrapper, 'MIN_ARIA').setValue('30');

    expect(rankInput(wrapper, 'MIN_ARIA').element.value).toBe('4');
  });

  it('aberto agora e tem horário só têm a opção sim', async () => {
    const wrapper = await mountSearchPage({
      searches: [bakerySearch()],
      payloads: {
        11: {
          search: bakerySearch(),
          leads: [
            sunLead({ has_opening_hours: true }),
            sunLead({
              id: 104,
              name: 'Sem Horário',
              open_now: true,
              has_opening_hours: false,
            }),
            sunLead({
              id: 105,
              name: 'Fechada',
              open_now: false,
              has_opening_hours: true,
            }),
          ],
        },
      },
    });
    await openResultFilters(wrapper);

    await checkYesOnly(wrapper, 'OPEN_NOW');
    await checkYesOnly(wrapper, 'HAS_OPENING_HOURS');
    await applyFilters(wrapper);

    expect(leadNames(wrapper)).toEqual(['Padaria Sol']);
    expect(filterBadge(wrapper)).toBe('2');
  });

  it('o formulário tem a própria gaveta: o pedido só leva o que foi aplicado', async () => {
    const wrapper = await openNewSearchForm();
    await openFormFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no');
    await checkYesOnly(wrapper, 'HAS_OPENING_HOURS');
    await applyFilters(wrapper);

    expect(filtersPanel(wrapper).exists()).toBe(false);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.ACTIVE_FILTERS');
    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.advanced_filters).toMatchObject({
      has_website: 'no',
      has_opening_hours: 'yes',
    });
  });

  it('fechar a gaveta do formulário sem Aplicar descarta o rascunho', async () => {
    const wrapper = await openNewSearchForm();
    await openFormFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no');
    await buttonWithTitle(wrapper, `${DRAWER}.CLOSE`).trigger('click');
    await flushPromises();

    const payload = await submitMinimalSearch(wrapper);
    expect(payload.metadata.advanced_filters.has_website).toBe('');
  });

  it('refino dos resultados não vaza para o formulário de nova busca', async () => {
    const wrapper = await mountSearchPage();
    await openResultFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE', 'yes');
    await applyFilters(wrapper);

    await toggleNewSearch(wrapper);
    await openFormFilters(wrapper);
    expect(
      choiceSelect(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_PHONE').props(
        'modelValue'
      )
    ).toBe('');
  });

  it('filtro aplicado no formulário não refina a busca aberta ao voltar', async () => {
    const wrapper = await mountSearchPage();
    await toggleNewSearch(wrapper);
    await openFormFilters(wrapper);
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.HAS_SITE', 'no');
    await applyFilters(wrapper);

    await toggleNewSearch(wrapper);

    expect(leadNames(wrapper)).toHaveLength(3);
    expect(filterBadge(wrapper)).toBe('');
    expect(AutonomiaProspectingAPI.createSearch).not.toHaveBeenCalled();
  });
});
