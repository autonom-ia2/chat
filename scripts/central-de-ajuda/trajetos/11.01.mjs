// Roteiro do vídeo de trajeto do artigo 11.01 — "Onde ficam os agentes de IA
// e como ler Meus agentes". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json e no componente
// AgentCard.vue (nome, bolinha de estado, selo "Copiloto da equipe",
// contagem de canais, botões Publicar/Apagar).
//
// Trajeto: barra lateral → Agentes → Meus agentes → leia os cards → abra um
// agente → veja Publicar/Apagar num rascunho → Criar agente com IA.

export const id = '11.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Garante, de forma idempotente, três agentes de exemplo com estados
// diferentes (Ativo com canal, Ativo interno com o selo de copiloto,
// Rascunho com Publicar/Apagar visíveis) — sem tocar nos agentes de outros
// vídeos (Lia Atendimento/Robô Renovação/Guia da Plataforma, ids 2/3/4).
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

vale = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: "Vale Copiloto")
vale.assign_attributes(
  agent_type: "custom",
  actuation: "internal",
  status: "active",
  enabled: true,
  mode: "guided",
  human_card: "Ajuda a equipe a responder mais rápido durante o atendimento.",
  greeting: "Oi, time! Pergunte o que precisar sobre a conversa atual.",
  starter_questions: ["Resuma esta conversa", "Sugira uma resposta"],
  instruction: "Ajude o atendente com resumos e sugestões de resposta durante o atendimento.",
  created_by_id: usuaria.id,
  config: { "with_knowledge" => false }
)
vale.save!
Autonomia::Agents::AgentInbox.where(autonomia_agent_id: vale.id).destroy_all

rascunho = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: "Bia Recepção")
rascunho.assign_attributes(
  agent_type: "reception",
  actuation: "external",
  status: "draft",
  enabled: false,
  mode: "guided",
  human_card: "Recebe, faz a triagem e direciona cada conversa.",
  greeting: "Oi! Já te encaminho para quem pode ajudar.",
  starter_questions: ["Quero falar sobre um sinistro", "Quero uma cotação"],
  instruction: "Recepcione o cliente, identifique o assunto e direcione para a equipe certa.",
  created_by_id: usuaria.id,
  config: { "with_knowledge" => false }
)
rascunho.save!
Autonomia::Agents::AgentInbox.where(autonomia_agent_id: rascunho.id).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ver seus agentes de IA',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Agentes na barra lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'Agentes' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Meus agentes',
    acao: 'mover e clicar',
    alvo: { texto: 'Meus agentes' },
    zoom: 2,
  },
  {
    legenda: 'Leia o nome e o estado do agente',
    acao: 'parar',
    alvo: { texto: 'Sol Atendimento' },
    zoom: 1.5,
    duracaoMs: 1800,
  },
  {
    legenda: 'Veja o selo Copiloto da equipe',
    acao: 'parar',
    alvo: { texto: 'Copiloto da equipe' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    // O backend ainda não envia `channels_count` no payload do agente (visto
    // ao gravar este vídeo — ver relato ao Rodrigo), então o card sempre
    // mostra "Nenhum canal", mesmo com uma caixa já conectada. É um dos
    // valores documentados no artigo, então a cena continua fiel à tela.
    legenda: 'Confira quantos canais ele atende',
    acao: 'parar',
    alvo: { texto: 'Nenhum canal' },
    zoom: 1.8,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique no card para abrir o agente',
    acao: 'mover e clicar',
    alvo: { texto: 'Sol Atendimento' },
    zoom: 1.6,
  },
  {
    legenda: 'Volte para Meus agentes',
    acao: 'mover e clicar',
    alvo: { texto: 'Meus agentes' },
    zoom: 1.8,
  },
  {
    legenda: 'Rascunho mostra Publicar e Apagar',
    acao: 'parar',
    alvo: { texto: 'Bia Recepção' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Criar agente com IA',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar agente com IA' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
