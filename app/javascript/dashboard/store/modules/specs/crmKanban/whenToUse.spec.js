import { actions } from '../../crmKanban';
import CrmKanbanAPI from '../../../../api/crmKanban';

vi.mock('../../../../api/crmKanban', () => ({
  default: {
    updatePipeline: vi.fn(),
    createPipeline: vi.fn(),
  },
}));

vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }));

// Multifunil (#1145): o "Quando usar" do funil vai para a API, e quem não manda o campo não o apaga.
describe('#savePipelineWithStages when_to_use', () => {
  const save = pipeline =>
    actions.savePipelineWithStages(
      { commit: vi.fn(), dispatch: vi.fn() },
      { pipeline, stages: [] }
    );

  beforeEach(() => {
    vi.clearAllMocks();
    CrmKanbanAPI.updatePipeline.mockResolvedValue({
      data: { payload: { id: 7 } },
    });
  });

  it('sends the text the person wrote, including an empty one', async () => {
    await save({ id: 7, name: 'Comercial', when_to_use: 'Agentes de IA' });
    await save({ id: 7, name: 'Comercial', when_to_use: '' });

    expect(CrmKanbanAPI.updatePipeline.mock.calls[0][1]).toMatchObject({
      when_to_use: 'Agentes de IA',
    });
    expect(CrmKanbanAPI.updatePipeline.mock.calls[1][1]).toMatchObject({
      when_to_use: '',
    });
  });

  it('leaves it out when the caller does not send it', async () => {
    await save({ id: 7, name: 'Comercial' });

    expect(CrmKanbanAPI.updatePipeline.mock.calls[0][1]).not.toHaveProperty(
      'when_to_use'
    );
  });
});
