// Pesquisa de empresa e decisor na tela de busca (#679, frente D): selos no
// card, barra de progresso, bloco no painel lateral, pedido pela API e
// atualização pelo evento prospecting.lead.updated. O texto real é conferido
// nos specs de componente; aqui vale a ligação da tela.
import { flushPromises } from '@vue/test-utils';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import {
  bakerySearch,
  buttonWithText,
  confirmation,
  detailPanel,
  gymSearch,
  hotBreadLead,
  leadCard,
  moonLead,
  mountSearchPage,
  settingsFixture,
  sunLead,
} from './support/searchPageHarness';
import {
  notResearched,
  queuedResearch,
  researchBlock,
} from './support/researchFixtures';

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

const mountWith = (leads, { search = bakerySearch(), settings } = {}) =>
  mountSearchPage({
    settings,
    payloads: {
      11: { search, leads },
      12: { search: gymSearch(), leads: [] },
    },
  });

const leadUpdated = async lead => {
  emitter.emit(BUS_EVENTS.PROSPECTING_LEAD_UPDATED, { account_id: 1, lead });
  await flushPromises();
};

const openDetails = async (wrapper, name) => {
  await buttonWithText(
    leadCard(wrapper, name),
    'PROSPECTING.SEARCH.OPEN_DETAILS'
  ).trigger('click');
  await flushPromises();
};

const badgeState = (element, kind) =>
  element.find(`[data-research-badge="${kind}"]`).attributes('data-state');
const progressBar = wrapper => wrapper.find('[role="progressbar"]');
const researchAction = wrapper =>
  detailPanel(wrapper).find('[data-test="research-action"]');

describe('ProspectingSearchPage · selos da pesquisa no card', () => {
  it('mostra os selos Empresa e Decisor do lead pesquisado', async () => {
    const wrapper = await mountWith([
      sunLead({ research: researchBlock({ decision_status: 'possible' }) }),
    ]);
    const card = leadCard(wrapper, 'Padaria Sol');

    expect(badgeState(card, 'company')).toBe('confirmed');
    expect(badgeState(card, 'decision')).toBe('possible');
    expect(card.text()).toContain('JOAO DA SILVA');
  });

  it('lead sem bloco research segue como antes, com o decisor do enriquecimento', async () => {
    const wrapper = await mountSearchPage();
    const card = leadCard(wrapper, 'Confeitaria Lua');

    expect(card.find('[data-test="lead-research"]').exists()).toBe(false);
    expect(card.text()).toContain('PROSPECTING.SEARCH.DECISION_MAKER');
    expect(card.text()).toContain('Ana');
  });

  it('com a pesquisa, o decisor antigo do enriquecimento sai do card', async () => {
    const wrapper = await mountWith([moonLead({ research: notResearched() })]);
    const card = leadCard(wrapper, 'Confeitaria Lua');

    expect(card.find('[data-test="lead-research"]').exists()).toBe(true);
    expect(card.text()).not.toContain('PROSPECTING.SEARCH.DECISION_MAKER');
    expect(card.text()).toContain('Atende eventos');
  });
});

describe('ProspectingSearchPage · barra de progresso', () => {
  it('aparece acima da lista com a contagem dos leads', async () => {
    const wrapper = await mountWith([
      sunLead({ research: researchBlock() }),
      hotBreadLead({
        research: queuedResearch({ company_status: 'researching' }),
      }),
      moonLead({ research: queuedResearch() }),
    ]);
    const bar = progressBar(wrapper);

    expect(bar.exists()).toBe(true);
    expect(bar.attributes('aria-valuemax')).toBe('3');
    expect(bar.attributes('aria-valuenow')).toBe('1');
    const list = wrapper.find('[data-test="research-progress"]').element;
    const firstCard = leadCard(wrapper, 'Padaria Sol').element;
    expect(list.compareDocumentPosition(firstCard)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    );
  });

  it('sem pesquisa, a barra não aparece', async () => {
    const wrapper = await mountWith([
      sunLead({ research: notResearched() }),
      hotBreadLead(),
    ]);

    expect(progressBar(wrapper).exists()).toBe(false);
  });

  it('usa o progresso da busca quando os leads ainda não trazem o bloco', async () => {
    const wrapper = await mountWith([sunLead(), hotBreadLead()], {
      search: bakerySearch({
        research_progress: {
          total: 2,
          done: 1,
          running: 1,
          queued: 0,
          failed: 0,
        },
      }),
    });

    expect(progressBar(wrapper).attributes('aria-valuenow')).toBe('1');
    expect(progressBar(wrapper).attributes('aria-valuemax')).toBe('2');
  });

  it('avança sozinha pelo evento, sem recarregar', async () => {
    const wrapper = await mountWith([
      sunLead({ research: queuedResearch() }),
      hotBreadLead({ research: queuedResearch() }),
    ]);
    expect(progressBar(wrapper).attributes('aria-valuenow')).toBe('0');

    await leadUpdated(
      sunLead({
        research: researchBlock({
          requested_at: '2026-09-25T12:00:00Z',
          completed_at: '2026-09-25T12:01:00Z',
        }),
      })
    );

    expect(progressBar(wrapper).attributes('aria-valuenow')).toBe('1');
    expect(badgeState(leadCard(wrapper, 'Padaria Sol'), 'company')).toBe(
      'confirmed'
    );
  });
});

describe('ProspectingSearchPage · pesquisa no painel lateral', () => {
  beforeEach(() => {
    useAlert.mockClear();
  });

  it('mostra quem atende e a empresa do lead aberto', async () => {
    const wrapper = await mountWith([sunLead({ research: researchBlock() })]);
    await openDetails(wrapper, 'Padaria Sol');
    const panel = detailPanel(wrapper);

    expect(panel.find('[data-test="research-owners"]').text()).toContain(
      'MARIA DA SILVA'
    );
    expect(panel.find('[data-test="research-company"]').text()).toContain(
      '12.345.678/0001-95'
    );
  });

  it('Pesquisar pede a pesquisa sem forçar e avisa que entrou na fila', async () => {
    const wrapper = await mountWith([sunLead({ research: notResearched() })]);
    AutonomiaProspectingAPI.researchLead.mockResolvedValue({
      status: 202,
      data: { payload: { lead: sunLead({ research: queuedResearch() }) } },
    });
    await openDetails(wrapper, 'Padaria Sol');

    await researchAction(wrapper).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.researchLead).toHaveBeenCalledWith(101, {
      force: false,
    });
    expect(useAlert).toHaveBeenCalledWith('PROSPECTING.RESEARCH.QUEUED_ALERT');
    expect(researchAction(wrapper).element.disabled).toBe(true);
    expect(badgeState(leadCard(wrapper, 'Padaria Sol'), 'company')).toBe(
      'queued'
    );
  });

  it('Verificar novamente confirma e força', async () => {
    const wrapper = await mountWith([sunLead({ research: researchBlock() })]);
    AutonomiaProspectingAPI.researchLead.mockResolvedValue({
      data: { payload: { lead: sunLead({ research: queuedResearch() }) } },
    });
    await openDetails(wrapper, 'Padaria Sol');

    await researchAction(wrapper).trigger('click');
    await flushPromises();

    expect(confirmation.calls).toBe(1);
    expect(AutonomiaProspectingAPI.researchLead).toHaveBeenCalledWith(101, {
      force: true,
    });
  });

  it('recusar a confirmação não chama a API', async () => {
    const wrapper = await mountWith([sunLead({ research: researchBlock() })]);
    await openDetails(wrapper, 'Padaria Sol');
    confirmation.answer = false;

    await researchAction(wrapper).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.researchLead).not.toHaveBeenCalled();
  });

  it('recusa do servidor (422) mostra o erro e deixa o lead como estava', async () => {
    const wrapper = await mountWith([sunLead({ research: notResearched() })]);
    AutonomiaProspectingAPI.researchLead.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Pesquisa desligada', code: 'research_disabled' },
      },
    });
    await openDetails(wrapper, 'Padaria Sol');

    await researchAction(wrapper).trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Pesquisa desligada');
    expect(researchAction(wrapper).element.disabled).toBe(false);
    expect(badgeState(leadCard(wrapper, 'Padaria Sol'), 'company')).toBe(
      'not_researched'
    );
  });

  it('pesquisa desligada na conta: botão desabilitado', async () => {
    const wrapper = await mountWith([sunLead({ research: notResearched() })], {
      settings: settingsFixture({ research_enabled: false }),
    });
    await openDetails(wrapper, 'Padaria Sol');

    expect(researchAction(wrapper).element.disabled).toBe(true);
  });

  it('o painel aberto troca pelo evento quando a pesquisa termina', async () => {
    const wrapper = await mountWith([sunLead({ research: queuedResearch() })]);
    await openDetails(wrapper, 'Padaria Sol');
    expect(
      detailPanel(wrapper).find('[data-test="research-company"]').exists()
    ).toBe(false);

    await leadUpdated(
      sunLead({
        research: researchBlock({
          requested_at: '2026-09-25T12:00:00Z',
          completed_at: '2026-09-25T12:01:00Z',
        }),
      })
    );

    expect(
      detailPanel(wrapper).find('[data-test="research-company"]').text()
    ).toContain('Padaria Sol Alimentos Ltda.');
  });

  it('resposta atrasada do pedido não desfaz o resultado que o evento trouxe', async () => {
    const wrapper = await mountWith([sunLead({ research: notResearched() })]);
    let resolveRequest;
    AutonomiaProspectingAPI.researchLead.mockReturnValue(
      new Promise(resolve => {
        resolveRequest = resolve;
      })
    );
    await openDetails(wrapper, 'Padaria Sol');
    await researchAction(wrapper).trigger('click');

    await leadUpdated(
      sunLead({
        research: researchBlock({
          requested_at: '2026-09-25T12:00:00Z',
          completed_at: '2026-09-25T12:01:00Z',
        }),
      })
    );
    resolveRequest({
      data: {
        payload: {
          lead: sunLead({
            research: queuedResearch({ requested_at: '2026-09-25T12:00:00Z' }),
          }),
        },
      },
    });
    await flushPromises();

    expect(badgeState(leadCard(wrapper, 'Padaria Sol'), 'company')).toBe(
      'confirmed'
    );
  });

  it('lead sem bloco research não mostra o bloco no painel', async () => {
    const wrapper = await mountSearchPage();
    await openDetails(wrapper, 'Padaria Sol');

    expect(
      detailPanel(wrapper).find('[data-test="lead-detail-research"]').exists()
    ).toBe(false);
  });
});
