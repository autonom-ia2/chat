// Caracterização das ações em lote (#677): seleção, envio ao CRM e CSV. O
// envio em si (janela, lotes e resumo) está em ProspectingSearchPage.crmSend e
// CrmSendModal (#680).
import { flushPromises } from '@vue/test-utils';
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
import {
  ADDRESS_SEPARATOR,
  captureCsvDownload,
  leadCheckbox,
  readBlob,
} from './support/resultsHelpers';

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

  it('exporta CSV de todos os leads visíveis, na ordem da tela', async () => {
    const wrapper = await mountSearchPage();
    const download = captureCsvDownload();

    await buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.CSV_EXPORT').trigger(
      'click'
    );
    const csv = await readBlob(download.blob);

    expect(download.fileName).toBe('prospeccao-11.csv');
    expect(download.clicks).toBe(1);
    expect(download.blob.type).toBe('text/csv;charset=utf-8;');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:csv');
    expect(csv.split('\n')).toEqual([
      'name,phone,website,address,status,source',
      `"Padaria Sol","(41) 99999-0001","https://sol.com.br","Rua A, 10${ADDRESS_SEPARATOR}Curitiba PR","new","Google Maps"`,
      `"Pão Quente","4133330002","","Rua B, 20${ADDRESS_SEPARATOR}Curitiba PR","contacted","google_places"`,
      `"Confeitaria Lua","","https://lua.com.br","Rua C, 30${ADDRESS_SEPARATOR}Curitiba","new","google_places"`,
    ]);
  });

  it('exporta só os selecionados e escapa aspas', async () => {
    const search = bakerySearch();
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: {
        11: {
          search,
          leads: [sunLead({ name: 'Padaria "Sol"' }), hotBreadLead()],
        },
      },
    });
    const download = captureCsvDownload();

    await leadCheckbox(wrapper, 'Padaria "Sol"').trigger('change');
    await buttonWithTitle(wrapper, 'PROSPECTING.SEARCH.CSV_EXPORT').trigger(
      'click'
    );
    const lines = (await readBlob(download.blob)).split('\n');

    expect(lines).toHaveLength(2);
    expect(lines[1].startsWith('"Padaria ""Sol""",')).toBe(true);
  });
});
