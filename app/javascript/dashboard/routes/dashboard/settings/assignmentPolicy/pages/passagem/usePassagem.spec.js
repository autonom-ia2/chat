import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { usePassagem } from './usePassagem';
import { ETAPA_DESLIGADA, ETAPA_IGUAL, ETAPA_PROPRIA } from './passagem';

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getAiSettings: vi.fn(),
    getPipelines: vi.fn(),
    updateAiSettings: vi.fn(),
  },
}));

const HANDOFF = {
  enabled: true,
  mode: 'round_robin',
  handoff_mode: 'r2_direct',
  trigger: '',
  prefer_online: true,
  pickup_threshold_seconds: 900,
  escalation_user_id: null,
  pool_type: 'inbox',
  pool_id: null,
  escalation_action: 'renotify',
};
const ajustes = {
  enabled: true,
  handoff: HANDOFF,
  inboxes: [{ id: 3, name: 'Site' }],
  team: [{ id: 7, name: 'Ana Ribeiro' }],
  stages: [
    { id: 1, name: 'Novo', handoff_custom: false, handoff: HANDOFF },
    {
      id: 2,
      name: 'Proposta',
      handoff_custom: true,
      handoff: { ...HANDOFF, handoff_mode: 'r3_invite' },
    },
    {
      id: 3,
      name: 'Fechado',
      handoff_custom: true,
      handoff: { ...HANDOFF, enabled: false },
    },
  ],
};

const resposta = payload => Promise.resolve({ data: { payload } });

describe('usePassagem', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmKanbanAPI.getAiSettings.mockImplementation(() => resposta(ajustes));
    CrmKanbanAPI.getPipelines.mockImplementation(() =>
      resposta([{ id: 9, name: 'Vendas' }])
    );
    CrmKanbanAPI.updateAiSettings.mockImplementation(() => resposta({}));
  });

  it('lê caixas, equipe e etapas só do ai_settings', async () => {
    // Arrange
    const passagem = usePassagem();

    // Act
    await passagem.carregar(9);

    // Assert
    expect(passagem.falhou.value).toBe(false);
    expect(passagem.caixas.value).toEqual([{ id: 3, name: 'Site' }]);
    expect(passagem.equipe.value).toEqual([{ id: 7, name: 'Ana Ribeiro' }]);
    expect(passagem.etapas.value.map(etapa => etapa.modo)).toEqual([
      ETAPA_IGUAL,
      ETAPA_PROPRIA,
      ETAPA_DESLIGADA,
    ]);
  });

  it('salva a regra do funil e a de cada etapa no formato do SettingsUpdater', async () => {
    // Arrange
    const passagem = usePassagem();
    await passagem.carregar(9);

    // Act
    const deuCerto = await passagem.salvar(9);

    // Assert
    expect(deuCerto).toBe(true);
    const [funil, corpo] = CrmKanbanAPI.updateAiSettings.mock.calls[0];
    expect(funil).toBe(9);
    expect(corpo.ai_settings.handoff).toMatchObject({
      enabled: true,
      handoff_mode: 'r2_direct',
    });
    expect(corpo.stage_handoff[1]).toEqual({ custom: false });
    expect(corpo.stage_handoff[2]).toMatchObject({
      custom: true,
      enabled: true,
      handoff_mode: 'r3_invite',
    });
    expect(corpo.stage_handoff[3]).toMatchObject({
      custom: true,
      enabled: false,
    });
    expect(passagem.alterado.value).toBe(false);
  });

  it('descarta a resposta de um funil antigo quando outro já foi pedido', async () => {
    // Arrange
    let soltarAntigo;
    CrmKanbanAPI.getAiSettings.mockImplementationOnce(
      () =>
        new Promise(soltar => {
          soltarAntigo = () =>
            soltar({ data: { payload: { ...ajustes, team: [] } } });
        })
    );
    const passagem = usePassagem();

    // Act
    const antigo = passagem.carregar(8);
    await passagem.carregar(9);
    soltarAntigo();
    await antigo;

    // Assert
    expect(passagem.equipe.value).toEqual([{ id: 7, name: 'Ana Ribeiro' }]);
    expect(passagem.carregando.value).toBe(false);
  });

  it('se o servidor recusar, avisa que não salvou', async () => {
    // Arrange
    const passagem = usePassagem();
    await passagem.carregar(9);
    CrmKanbanAPI.updateAiSettings.mockImplementationOnce(() =>
      Promise.reject(new Error('422'))
    );

    // Act
    const deuCerto = await passagem.salvar(9);

    // Assert
    expect(deuCerto).toBe(false);
    expect(passagem.salvando.value).toBe(false);
  });
});
