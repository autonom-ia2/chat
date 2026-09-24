// Ajudantes do formulário de nova busca, compartilhados pelos specs de payload
// por frente (#677). Cada frente da E1 confere o próprio pedaço do pedido num
// arquivo só dela, sem editar o teste de payload exato da linha de base.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import {
  bakerySearch,
  buttonWithText,
  mountSearchPage,
  toggleNewSearch,
  waitLocationDebounce,
} from './searchPageHarness';

export const LOCATION_DETAILS = {
  label: 'Curitiba, PR, Brasil',
  place_id: 'place-cwb',
  latitude: '-25.4284',
  longitude: '-49.2733',
};

export const queryInput = wrapper =>
  wrapper.find('input[placeholder="PROSPECTING.SEARCH.QUERY_PLACEHOLDER"]');

export const locationInput = wrapper =>
  wrapper.find('input[placeholder="PROSPECTING.SEARCH.LOCATION_PLACEHOLDER"]');

export const openNewSearchForm = async (options = {}) => {
  const wrapper = await mountSearchPage({ searches: [], ...options });
  await toggleNewSearch(wrapper);
  return wrapper;
};

export const confirmCuritiba = async wrapper => {
  AutonomiaProspectingAPI.getLocationSuggestions.mockResolvedValue({
    data: { payload: [{ text: 'Curitiba, PR', place_id: 'place-cwb' }] },
  });
  AutonomiaProspectingAPI.getLocationDetails.mockResolvedValue({
    data: { payload: LOCATION_DETAILS },
  });
  await locationInput(wrapper).setValue('Curi');
  await waitLocationDebounce();
  await buttonWithText(wrapper, 'Curitiba, PR').trigger('click');
  await flushPromises();
};

// Preenche o mínimo que libera a busca, envia e devolve o corpo do pedido.
export const submitMinimalSearch = async (wrapper, query = 'padaria') => {
  AutonomiaProspectingAPI.createSearch.mockResolvedValue({
    data: { payload: { search: bakerySearch(), leads: [] } },
  });
  await queryInput(wrapper).setValue(query);
  await confirmCuritiba(wrapper);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  const { calls } = AutonomiaProspectingAPI.createSearch.mock;
  return calls[calls.length - 1][0];
};
