// Caracterização das ações em lote (#677): seleção, envio ao CRM e exportação. O
// envio em si (janela, lotes e resumo) está em ProspectingSearchPage.crmSend e
// CrmSendModal (#680).
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import CrmSendModal from '../components/crm/CrmSendModal.vue';
import {
  bakerySearch,
  buttonWithText,
  buttonWithTitle,
  hotBreadLead,
  leadCard,
  leadCards,
  mountSearchPage,
  settingsFixture,
  sunLead,
} from './support/searchPageHarness';
import { captureCsvDownload, leadCheckbox } from './support/resultsHelpers';

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

describe('ProspectingSearchPage · ações em lote', () => {
  beforeEach(() => {
    permission.canManage = true;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('seleciona um lead, seleciona todos os visíveis e limpa a seleção', async () => {
    const wrapper = await mountSearchPage();
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.SELECTED_COUNT');

    await leadCheckbox(wrapper, 'Pão Quente').trigger('change');
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.SELECTED_COUNT');
    expect(leadCheckbox(wrapper, 'Pão Quente').element.checked).toBe(true);
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.SEND_TO_CRM')
    ).toBeTruthy();

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    expect(
      leadCards(wrapper).map(
        card => card.find('input[type="checkbox"]').element.checked
      )
    ).toEqual([true, true, true]);

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    expect(
      leadCards(wrapper).map(
        card => card.find('input[type="checkbox"]').element.checked
      )
    ).toEqual([false, false, false]);
    expect(wrapper.text()).not.toContain('PROSPECTING.SEARCH.SELECTED_COUNT');
  });

  it('a janela sugere o funil e o estágio configurados na própria busca', async () => {
    const search = bakerySearch({ crm_pipeline_id: 4, crm_stage_id: 41 });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [sunLead()] } },
    });

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SEND_TO_CRM').trigger(
      'click'
    );
    await flushPromises();

    const modal = wrapper.findComponent(CrmSendModal);
    expect(modal.props('suggestedPipelineId')).toBe(4);
    expect(modal.props('suggestedStageId')).toBe(41);
  });

  it('sem funil definido a janela abre sem sugestão, para a pessoa escolher', async () => {
    const wrapper = await mountSearchPage({
      settings: settingsFixture({
        default_crm_pipeline_id: null,
        default_crm_stage_id: null,
      }),
    });

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.SEND_TO_CRM'
    ).trigger('click');
    await flushPromises();

    const modal = wrapper.findComponent(CrmSendModal);
    expect(modal.props('suggestedPipelineId')).toBe('');
    expect(modal.props('suggestedStageId')).toBe('');
  });

  // Exportação pelo servidor (#682): o botão oferece CSV e Excel, e a tela
  // manda os leads que exportaria antes, os visíveis ou os selecionados, na
  // ordem dela. O arquivo vem pronto do servidor.
  const chooseExport = async (wrapper, format) => {
    await buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.CSV_EXPORT').trigger(
      'click'
    );
    await buttonWithText(
      wrapper,
      `PROSPECTING.SEARCH.EXPORT_${format.toUpperCase()}`
    ).trigger('click');
    await flushPromises();
  };

  it('o botão de download oferece CSV e Excel', async () => {
    const wrapper = await mountSearchPage();

    await buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.CSV_EXPORT').trigger(
      'click'
    );

    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.EXPORT_CSV')
    ).toBeTruthy();
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.EXPORT_XLSX')
    ).toBeTruthy();
    expect(AutonomiaProspectingAPI.exportSearch).not.toHaveBeenCalled();
  });

  it('exporta CSV de todos os leads visíveis, na ordem da tela', async () => {
    const wrapper = await mountSearchPage();
    const download = captureCsvDownload();
    const file = new Blob(['csv do servidor'], { type: 'text/csv' });
    AutonomiaProspectingAPI.exportSearch.mockResolvedValue({ data: file });
    // A ordem da tela: Padaria Sol, Pão Quente, Confeitaria Lua.
    const visibleIds = [101, 102, 103];

    await chooseExport(wrapper, 'csv');

    expect(AutonomiaProspectingAPI.exportSearch).toHaveBeenCalledWith(11, {
      format: 'csv',
      leadIds: visibleIds,
    });
    expect(download.blob).toBe(file);
    expect(download.fileName).toBe('prospeccao-11.csv');
    expect(download.clicks).toBe(1);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:csv');
    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.EXPORT_CSV')
    ).toBeFalsy();
  });

  it('exporta em Excel só os selecionados', async () => {
    const search = bakerySearch();
    const selected = sunLead({ name: 'Padaria "Sol"' });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [selected, hotBreadLead()] } },
    });
    const download = captureCsvDownload();
    AutonomiaProspectingAPI.exportSearch.mockResolvedValue({
      data: new Blob(['xlsx']),
    });

    await leadCheckbox(wrapper, 'Padaria "Sol"').trigger('change');
    await chooseExport(wrapper, 'xlsx');

    expect(AutonomiaProspectingAPI.exportSearch).toHaveBeenCalledWith(11, {
      format: 'xlsx',
      leadIds: [selected.id],
    });
    expect(download.fileName).toBe('prospeccao-11.xlsx');
  });

  it('falha no servidor avisa e não baixa nada', async () => {
    const wrapper = await mountSearchPage();
    const download = captureCsvDownload();
    AutonomiaProspectingAPI.exportSearch.mockRejectedValue(new Error('500'));

    await chooseExport(wrapper, 'csv');

    expect(useAlert).toHaveBeenCalledWith('PROSPECTING.SEARCH.EXPORT_ERROR');
    expect(download.clicks).toBe(0);
  });
});
