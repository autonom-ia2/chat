// Roteiro do vídeo de trajeto do artigo 11.11 — "Pausar, reativar, apagar e
// usar como copiloto". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json (AGENTS.PANEL,
// AGENTS.HUB.DELETE_DIALOG).
//
// O botão do Copiloto Autonom.ia dentro da conversa (i-lucide-sparkles) fica
// atrás da flag global CRM_COPILOT_ENABLED, que está desligada nesta
// instalação local (não dá pra ligar via preparar/banco — é variável de
// ambiente do servidor). Por isso este vídeo cobre só pausar/reativar/
// apagar; o trecho do copiloto na conversa fica para o artigo [08.13], como
// o próprio texto do 11.11 já aponta.
//
// Trajeto: agente já publicado → Pausar → Ativar → Meus agentes → Apagar →
// confirmar em Apagar agente?.

export const id = '11.11';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Recria um agente descartável a cada gravação — este vídeo APAGA o agente
// no fim, então cada execução precisa de um novo "Pedro Suporte".
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria

inbox = conta.inboxes.find_by(name: "Email Renovação")
raise "inbox Email Renovação não encontrada" unless inbox

Autonomia::Agents::Agent.where(account_id: conta.id, name: "Pedro Suporte").find_each do |antigo|
  Autonomia::Agents::AgentInbox.where(autonomia_agent_id: antigo.id).each do |ai|
    Autonomia::Agents::Operate::InboxConnector.new(agent: antigo, inbox: ai.inbox).perform(connect: false)
  end
  antigo.destroy!
end

pedro = Autonomia::Agents::Agent.create!(
  account_id: conta.id,
  name: "Pedro Suporte",
  agent_type: "support",
  actuation: "external",
  status: "active",
  enabled: true,
  mode: "guided",
  human_card: "Responde dúvidas sobre pedidos e prazos de entrega.",
  greeting: "Oi! Sou o assistente da loja. Como posso ajudar?",
  starter_questions: ["Qual o prazo de entrega?", "Como rastreio meu pedido?"],
  instruction: "Responda dúvidas sobre pedidos e prazos de entrega. Seja breve e cordial.",
  created_by_id: usuaria.id,
  config: { "with_knowledge" => false }
)
Autonomia::Agents::Operate::InboxConnector.new(agent: pedro, inbox: inbox).perform(connect: true)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Pausar, reativar e apagar um agente',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Meus agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/agents`,
    aguardarTexto: 'Pedro Suporte',
    zoom: 1,
    duracaoMs: 900,
  },
  {
    legenda: 'Abra o agente Pedro Suporte',
    acao: 'mover e clicar',
    alvo: { texto: 'Pedro Suporte' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Pausar no cabeçalho',
    acao: 'mover e clicar',
    alvo: { texto: 'Pausar' },
    zoom: 1.8,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Clique em Ativar para reverter',
    acao: 'mover e clicar',
    alvo: { texto: 'Ativar' },
    zoom: 1.8,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Volte para Meus agentes',
    acao: 'mover e clicar',
    alvo: { texto: 'Meus agentes' },
    zoom: 1.8,
  },
  {
    // A lista vem ordenada por created_at desc (AgentsController#index) e o
    // Pedro acabou de ser criado no preparar, então é o primeiro card — e o
    // primeiro botão "Apagar" no documento é o dele.
    legenda: 'Clique em Apagar no card',
    acao: 'mover e clicar',
    alvo: { texto: 'Apagar' },
    zoom: 1.6,
  },
  {
    legenda: 'Confira o nome em Apagar agente?',
    acao: 'parar',
    alvo: { texto: 'Apagar agente?' },
    zoom: 1.5,
    duracaoMs: 1600,
  },
  {
    // O botão de confirmar, dentro da caixa, é o único "Apagar" que é
    // type="submit" na tela (o botão do card é type="button") — evita
    // ambiguidade com o texto igual do card.
    legenda: 'Confirme em Apagar',
    acao: 'mover e clicar',
    alvo: { seletor: 'dialog[open] button[type="submit"]' },
    zoom: 1.6,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
];
