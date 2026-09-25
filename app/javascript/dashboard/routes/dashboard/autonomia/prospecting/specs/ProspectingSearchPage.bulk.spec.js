// Caracterização das ações em lote (#677): seleção, envio ao CRM e CSV.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import {
  bakerySearch,
  buttonWithText,
  buttonWithTitle,
  deferred,
  hotBreadLead,
  leadCard,
  leadCards,
  mountSearchPage,
  moonLead,
  settingsFixture,
  sunLead,
} from './support/searchPageHarness';
import {
  ADDRESS_SEPARATOR,
  captureCsvDownload,
  leadCheckbox,
  linkWithText,
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
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS')
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

  it('envia ao CRM em lote só os leads sem card, em sequência, no funil e estágio padrão', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.createLeadCrmCard.mockImplementation(leadId =>
      Promise.resolve({
        data: {
          payload: {
            lead: (leadId === 101 ? sunLead : moonLead)({
              crm_card_id: leadId * 10,
            }),
          },
        },
      })
    );

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.SELECT_VISIBLE').trigger(
      'click'
    );
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.createLeadCrmCard.mock.calls).toEqual([
      [101, { pipeline_id: 3, stage_id: 31 }],
      [103, { pipeline_id: 3, stage_id: 31 }],
    ]);
    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.CRM_CARD_CREATED'
    );
    expect(
      linkWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.OPEN_CRM_CARD'
      ).attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=1010');
  });

  it('usa o funil e o estágio configurados na própria busca', async () => {
    const search = bakerySearch({ crm_pipeline_id: 4, crm_stage_id: 41 });
    const wrapper = await mountSearchPage({
      searches: [search],
      payloads: { 11: { search, leads: [sunLead()] } },
    });
    AutonomiaProspectingAPI.createLeadCrmCard.mockResolvedValue({
      data: { payload: { lead: sunLead({ crm_card_id: 9 }) } },
    });

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');
    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaProspectingAPI.createLeadCrmCard).toHaveBeenCalledWith(
      101,
      {
        pipeline_id: 4,
        stage_id: 41,
      }
    );
  });

  it('sem funil definido bloqueia o envio ao CRM no lote e no card', async () => {
    const wrapper = await mountSearchPage({
      settings: settingsFixture({
        default_crm_pipeline_id: null,
        default_crm_stage_id: null,
      }),
    });

    await leadCheckbox(wrapper, 'Padaria Sol').trigger('change');

    expect(
      buttonWithText(wrapper, 'PROSPECTING.SEARCH.BULK_CRM_CARDS').element
        .disabled
    ).toBe(true);
    expect(
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.CREATE_CRM_CARD'
      ).element.disabled
    ).toBe(true);
  });

  it('cria o card de um lead pelo próprio card e troca o botão pelo link', async () => {
    const wrapper = await mountSearchPage();
    AutonomiaProspectingAPI.createLeadCrmCard.mockResolvedValue({
      data: { payload: { lead: sunLead({ crm_card_id: 777 }) } },
    });

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.CREATE_CRM_CARD'
    ).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createLeadCrmCard).toHaveBeenCalledWith(
      101,
      {
        pipeline_id: 3,
        stage_id: 31,
      }
    );
    expect(useAlert).toHaveBeenCalledWith(
      'PROSPECTING.SEARCH.CRM_CARD_CREATED'
    );
    expect(
      linkWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.OPEN_CRM_CARD'
      ).attributes('href')
    ).toBe('/app/accounts/1/crm?card_id=777');
  });

  it('mostra criando enquanto espera e avisa o erro da API ao criar o card', async () => {
    const wrapper = await mountSearchPage();
    const pending = deferred();
    AutonomiaProspectingAPI.createLeadCrmCard.mockReturnValue(pending.promise);

    await buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.CREATE_CRM_CARD'
    ).trigger('click');
    await flushPromises();
    const creating = buttonWithText(
      leadCard(wrapper, 'Padaria Sol'),
      'PROSPECTING.SEARCH.CREATING_CRM_CARD'
    );
    expect(creating.element.disabled).toBe(true);

    pending.reject({ response: { data: { error: 'Estágio inválido' } } });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Estágio inválido');
    expect(
      buttonWithText(
        leadCard(wrapper, 'Padaria Sol'),
        'PROSPECTING.SEARCH.CREATE_CRM_CARD'
      ).element.disabled
    ).toBe(false);
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
