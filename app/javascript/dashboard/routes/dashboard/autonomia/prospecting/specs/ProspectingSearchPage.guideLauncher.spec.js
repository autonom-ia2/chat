// As gavetas do canto direito avisam que estão abertas, para o lançador do Guia
// (#646) sair de cima dos botões delas. Achado em produção no #699: a bolinha
// do Guia cobria o Aplicar da gaveta de filtros.
import { flushPromises } from '@vue/test-utils';
import { isFixedPanelOpen } from 'dashboard/composables/useFixedPanelState';
import {
  buttonWithText,
  leadCard,
  mountSearchPage,
  sunLead,
} from './support/searchPageHarness';
import { openNewSearchForm } from './support/searchFormHelpers';
import { openFormFilters } from './support/filtersHelpers';

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

const overlay = wrapper => wrapper.find('div.fixed.inset-0');

describe('ProspectingSearchPage · lançador do Guia', () => {
  it('a gaveta de filtros avisa enquanto está aberta', async () => {
    const wrapper = await openNewSearchForm();
    expect(isFixedPanelOpen.value).toBe(false);

    await openFormFilters(wrapper);
    expect(isFixedPanelOpen.value).toBe(true);

    await overlay(wrapper).trigger('click');
    await flushPromises();
    expect(isFixedPanelOpen.value).toBe(false);
    wrapper.unmount();
  });

  it('o painel lateral do lead avisa enquanto está aberto', async () => {
    const wrapper = await mountSearchPage({ leads: [sunLead()] });
    expect(isFixedPanelOpen.value).toBe(false);

    await buttonWithText(
      leadCard(wrapper, sunLead().name),
      'PROSPECTING.SEARCH.OPEN_DETAILS'
    ).trigger('click');
    await flushPromises();
    expect(isFixedPanelOpen.value).toBe(true);

    await overlay(wrapper).trigger('click');
    await flushPromises();
    expect(isFixedPanelOpen.value).toBe(false);
    wrapper.unmount();
  });
});
