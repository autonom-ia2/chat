import prospecting from '../autonomiaProspecting';
import ApiClient from '../ApiClient';

// Pedido de pesquisa de empresa e decisor (#679). O servidor responde 202 e a
// pesquisa roda em fila; force ignora o resultado guardado.
describe('#AutonomiaProspectingAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/prospecting');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('é um cliente com escopo de conta', () => {
    expect(prospecting).toBeInstanceOf(ApiClient);
    expect(prospecting).toHaveProperty('researchLead');
  });

  it('pede a pesquisa do lead sem forçar por padrão', () => {
    prospecting.researchLead(7);

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/prospecting/leads/7/research',
      { force: false }
    );
  });

  it('pede a pesquisa forçada para verificar novamente', () => {
    prospecting.researchLead(7, { force: true });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/prospecting/leads/7/research',
      { force: true }
    );
  });

  // Envio ao CRM em lote, campanha da seleção e sócio como contato (#680).
  it('manda os leads ao CRM em lote com funil e estágio', () => {
    prospecting.createCrmCards({ leadIds: [1, 2], pipelineId: 3, stageId: 31 });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/prospecting/leads/crm_cards',
      { lead_ids: [1, 2], pipeline_id: 3, stage_id: 31 }
    );
  });

  it('adiciona os leads da seleção a uma campanha', () => {
    prospecting.addLeadsToCampaign({
      leadIds: [1, 2],
      campaignId: 8,
      segmentName: 'Padarias',
    });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/prospecting/leads/campaign_segment',
      { lead_ids: [1, 2], campaign_id: 8, segment_name: 'Padarias' }
    );
  });

  it('adota um sócio da pesquisa como contato do lead', () => {
    prospecting.adoptOwner(7, 'MARIA DA SILVA');

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/autonomia/prospecting/leads/7/adopt_owner',
      { owner_name: 'MARIA DA SILVA' }
    );
  });
});
