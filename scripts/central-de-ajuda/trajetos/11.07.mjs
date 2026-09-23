// Roteiro do vídeo de trajeto do artigo 11.07 — "O painel do agente: abas e
// estados". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json (AGENTS.PANEL).
//
// Trajeto: Meus agentes → Sol Atendimento → abas Testar/Conhecimento/
// Canais/Desempenho → Ajustar → Pausar → Ativar (volta ao estado normal).

export const id = '11.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Garante o Sol Atendimento ativo e conectado (externo, com base) — mesmo
// fixture usado por 11.01/11.08/11.10. Idempotente: este vídeo pausa e
// reativa o agente, então preparar sempre o encontra de volta Ativo.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria

inbox = conta.inboxes.find_by(name: "Instagram Loja")
raise "inbox Instagram Loja não encontrada" unless inbox

sol = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: "Sol Atendimento")
sol.assign_attributes(
  agent_type: "support",
  actuation: "external",
  status: "active",
  enabled: true,
  mode: "guided",
  human_card: "Responde dúvidas sobre horário de atendimento e como acionar o sinistro.",
  greeting: "Olá! Sou o assistente da Corretora Desnorteada. Como posso ajudar?",
  starter_questions: ["Qual o horário de atendimento?", "Como acionar um sinistro?"],
  instruction: "Responda dúvidas gerais sobre a corretora fictícia Corretora Desnorteada. Seja breve e cordial.",
  fallback_message: "Desculpe, não entendi. Vou chamar um colega de equipe.",
  created_by_id: usuaria.id,
  config: { "with_knowledge" => true }
)
sol.save!
unless Autonomia::Agents::AgentInbox.exists?(autonomia_agent_id: sol.id, inbox_id: inbox.id)
  Autonomia::Agents::Operate::InboxConnector.new(agent: sol, inbox: inbox).perform(connect: true)
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Conhecer o painel do agente',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Meus agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/agents`,
    aguardarTexto: 'Sol Atendimento',
    zoom: 1,
    duracaoMs: 900,
  },
  {
    legenda: 'Abra o agente Sol Atendimento',
    acao: 'mover e clicar',
    alvo: { texto: 'Sol Atendimento' },
    zoom: 1.6,
  },
  {
    legenda: 'Circule pelas abas: Testar',
    acao: 'mover e clicar',
    alvo: { texto: 'Testar' },
    zoom: 1.8,
  },
  {
    legenda: 'Conhecimento',
    acao: 'mover e clicar',
    alvo: { texto: 'Conhecimento' },
    zoom: 1.8,
  },
  {
    legenda: 'Canais',
    acao: 'mover e clicar',
    alvo: { texto: 'Canais' },
    zoom: 1.8,
  },
  {
    legenda: 'Desempenho',
    acao: 'mover e clicar',
    alvo: { texto: 'Desempenho' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Ajustar para editar',
    acao: 'mover e clicar',
    alvo: { texto: 'Ajustar' },
    zoom: 1.8,
  },
  {
    legenda: 'Use Pausar para trocar o estado',
    acao: 'mover e clicar',
    alvo: { texto: 'Pausar' },
    zoom: 1.8,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Estado muda no cabeçalho',
    acao: 'parar',
    alvo: { texto: 'Pausado' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Ativar para voltar',
    acao: 'mover e clicar',
    alvo: { texto: 'Ativar' },
    zoom: 1.8,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
];
