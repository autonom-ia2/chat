import {
  agentesParaFormulario,
  alternarFunilDoAgente,
  formularioDaCaixa,
  funisSemAgente,
  mudancasDosAgentes,
  salvarDaCaixa,
  tirarDaCaixa,
  voltarParaCaixa,
} from '../helpers/agentesIa';
import { juntar } from '../helpers/caixa';

const FUNIS = [
  { id: 1, name: 'Comercial', stages: [{ id: 11, name: 'Novo' }] },
  { id: 2, name: 'Financeiro', stages: [{ id: 21, name: 'Novo' }] },
  { id: 3, name: 'Suporte', stages: [{ id: 31, name: 'Novo' }] },
];

const aiAgents = (extra = {}) => ({
  porta: { id: 9, name: 'Clara' },
  pode_mudar: true,
  areas: [
    {
      id: 1,
      name: 'Maria',
      pipeline_ids: [1],
      parado: false,
      ultima_caixa: true,
    },
  ],
  disponiveis: [{ id: 2, name: 'Marta', parado: true }],
  ...extra,
});

const caixa = (ai = aiAgents()) => ({
  inbox: { id: 7, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
  crm_enabled: true,
  pipeline_ids: [1, 2, 3],
  default_stage_id: null,
  subject_ai_mode: 'auto',
  auto_create_card: false,
  visibility_mode: 'all_inbox_cards',
  agent_bot: { id: 99, name: 'Clara' },
  people: [],
  ...(ai ? { ai_agents: ai } : {}),
});

const agentes = () => agentesParaFormulario(aiAgents()).agentes;

describe('agentes de IA da caixa', () => {
  it('puts the inbox areas and the other agents in one list', () => {
    expect(
      agentes().map(({ name, na_caixa: naCaixa }) => [name, naCaixa])
    ).toEqual([
      ['Maria', true],
      ['Marta', false],
    ]);
  });

  it('moves a pipeline from one agent to another and says from whom', () => {
    const { agentes: novos, tirouDe } = alternarFunilDoAgente(agentes(), 2, 1);
    expect(novos.map(agente => agente.pipeline_ids)).toEqual([[], [1]]);
    expect(tirouDe.name).toBe('Maria');
  });

  it('unmarks a pipeline without touching the other agent', () => {
    const { agentes: novos, tirouDe } = alternarFunilDoAgente(agentes(), 1, 1);
    expect(novos.map(agente => agente.pipeline_ids)).toEqual([[], []]);
    expect(tirouDe).toBeNull();
  });

  it('lists the pipelines that stay with the door agent', () => {
    expect(funisSemAgente(agentes(), FUNIS).map(funil => funil.name)).toEqual([
      'Financeiro',
      'Suporte',
    ]);
  });

  it('removes an agent from the inbox and undoes it without taking pipelines back from others', () => {
    const fora = tirarDaCaixa(agentes(), 1);
    expect(fora[0]).toMatchObject({ sai: true, pipeline_ids: [] });
    expect(voltarParaCaixa(fora, 1)[0]).toMatchObject({
      sai: false,
      pipeline_ids: [1],
    });

    const outroPegou = alternarFunilDoAgente(fora, 2, 1).agentes;
    expect(voltarParaCaixa(outroPegou, 1)[0].pipeline_ids).toEqual([]);
  });

  it('sends the agents that stay or join, with pipelines of this inbox', () => {
    const original = formularioDaCaixa(caixa());
    const form = formularioDaCaixa(caixa());
    form.ai_agents.agentes = alternarFunilDoAgente(
      form.ai_agents.agentes,
      2,
      2
    ).agentes;
    expect(salvarDaCaixa(form, original).ai_agents).toEqual([
      { id: 1, pipeline_ids: [1] },
      { id: 2, pipeline_ids: [2] },
    ]);

    form.ai_agents.agentes = tirarDaCaixa(form.ai_agents.agentes, 1);
    expect(salvarDaCaixa(form, original).ai_agents).toEqual([
      { id: 2, pipeline_ids: [2] },
    ]);
  });

  it('does not bring in an agent whose only pipeline left the inbox', () => {
    const original = formularioDaCaixa(caixa());
    const form = formularioDaCaixa(caixa());
    form.ai_agents.agentes = alternarFunilDoAgente(
      form.ai_agents.agentes,
      2,
      3
    ).agentes;
    form.pipeline_ids = [1, 2];

    expect(salvarDaCaixa(form, original)).not.toHaveProperty('ai_agents');
    expect(mudancasDosAgentes(original, form, FUNIS, 'pt_BR')).toEqual([]);
  });

  it('sends nothing about agents when they did not change', () => {
    const original = formularioDaCaixa(caixa());
    const form = formularioDaCaixa(caixa());
    form.modo = 'off';

    expect(salvarDaCaixa(form, original)).not.toHaveProperty('ai_agents');
  });

  it('sends nothing about agents without phase 2 or without permission', () => {
    const sem = formularioDaCaixa(caixa(null));
    expect(salvarDaCaixa(sem, sem)).not.toHaveProperty('ai_agents');

    const leitura = formularioDaCaixa(caixa(aiAgents({ pode_mudar: false })));
    leitura.ai_agents.agentes = tirarDaCaixa(leitura.ai_agents.agentes, 1);
    expect(salvarDaCaixa(leitura, leitura)).not.toHaveProperty('ai_agents');
  });

  it('describes who joins, who leaves and who stops', () => {
    const antes = formularioDaCaixa(caixa());
    const depois = formularioDaCaixa(caixa());
    depois.ai_agents.agentes = tirarDaCaixa(
      alternarFunilDoAgente(depois.ai_agents.agentes, 2, 1).agentes,
      1
    );
    expect(mudancasDosAgentes(antes, depois, FUNIS, 'pt_BR')).toEqual([
      { chave: 'AGENTE_PARA', valores: { nome: 'Maria' } },
      { chave: 'AGENTE_ENTRA_E_LIGA', valores: { nome: 'Marta' } },
      {
        chave: 'PESSOA_GANHA',
        valores: { nome: 'Marta', assuntos: 'Comercial' },
      },
    ]);
  });

  it('joins the people who take over with "ou"', () => {
    expect(juntar(['Bruno', 'Diego'], 'pt_BR', 'disjunction')).toBe(
      'Bruno ou Diego'
    );
  });
});
