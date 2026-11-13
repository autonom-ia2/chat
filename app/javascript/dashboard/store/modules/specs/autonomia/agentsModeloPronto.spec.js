import autonomiaAgents from '../../autonomiaAgents';
import AutonomiaAgentsAPI from '../../../../api/autonomia/agents';
import { generateMutationTypes } from '../../../storeFactory';

// #2881 — rascunho reaberto de um agente pronto por ramo: as listas do modelo são gravadas pelo próprio agente, e a
// resposta (o agente, com o `modelo_pronto` novo) entra na lista de registros.
vi.mock('../../../../api/autonomia/agents', () => ({
  default: { mudarModeloPronto: vi.fn() },
}));

const { UPSERT } = generateMutationTypes('AutonomiaAgents');
const { mudarModeloPronto } = autonomiaAgents.actions;

describe('#autonomiaAgents store — mudarModeloPronto', () => {
  beforeEach(() => vi.clearAllMocks());

  it('patches the lists through the agent and upserts the agent the server answered', async () => {
    const commit = vi.fn();
    const listas = { documentos: [{ id: 'd1', texto: 'CRLV', tirada: true }] };
    const agente = { id: 7, modelo_pronto: { chave: 'seguro_auto' } };
    AutonomiaAgentsAPI.mudarModeloPronto.mockResolvedValue({ data: agente });

    const devolvido = await mudarModeloPronto(
      { commit },
      { agentId: 7, listas }
    );

    expect(AutonomiaAgentsAPI.mudarModeloPronto).toHaveBeenCalledWith(
      7,
      listas
    );
    expect(commit).toHaveBeenCalledWith(UPSERT, agente);
    expect(devolvido).toBe(agente);
  });

  it('rethrows the raw error and keeps the record as it was', async () => {
    const erro = {
      response: { status: 422, data: { motivo: 'lista_invalida' } },
    };
    AutonomiaAgentsAPI.mudarModeloPronto.mockRejectedValue(erro);
    const commit = vi.fn();

    await expect(
      mudarModeloPronto({ commit }, { agentId: 7, listas: {} })
    ).rejects.toBe(erro);
    expect(commit).not.toHaveBeenCalled();
  });
});
