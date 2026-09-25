// Ajudantes da gaveta de filtros (#677, frente B): o rascunho só vale depois de
// "Aplicar", então os specs escolhem e aplicam.
import { flushPromises } from '@vue/test-utils';
import { buttonWithText } from './searchPageHarness';

export const DRAWER = 'PROSPECTING.SEARCH.FILTER_DRAWER';

export const filtersPanel = wrapper =>
  wrapper.findComponent({ name: 'LeadFiltersPanel' });

export const clickPanelButton = async (wrapper, key) => {
  await buttonWithText(filtersPanel(wrapper), `${DRAWER}.${key}`).trigger(
    'click'
  );
  await flushPromises();
};

export const applyFilters = wrapper => clickPanelButton(wrapper, 'APPLY');

export const openFormFilters = async wrapper => {
  await buttonWithText(wrapper, `${DRAWER}.OPEN`).trigger('click');
  await flushPromises();
};

// Aberto agora e tem horário: caixa única "sim".
export const checkYesOnly = async (wrapper, key) => {
  const label = filtersPanel(wrapper)
    .findAll('label')
    .find(item => item.text().includes(`${DRAWER}.${key}`));
  await label.find('input[type="checkbox"]').setValue(true);
  await flushPromises();
};

export const rankInput = (wrapper, key) =>
  filtersPanel(wrapper).find(`input[aria-label="${DRAWER}.RANK.${key}"]`);

export const reviewsMinInput = wrapper =>
  filtersPanel(wrapper).find('input[type="number"]');
