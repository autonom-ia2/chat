// Roteiro do vídeo de trajeto do artigo 11.04 — "Ler o parecer de cada
// material". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json (AGENTS.MATERIALS)
// e no componente MaterialCard.vue (ícone/rótulo/motivo por estado).
//
// O artigo aponta o painel de materiais DENTRO do Construtor
// (BuilderKnowledgePanel, ao lado do chat). Esse caminho exige entrar em
// AgentBuilderPage — que, para QUALQUER agente (novo ou já existente), roda
// `startThread()` no onMounted sempre que `agentType` já está definido (ver
// comentário "IA-FALA-PRIMEIRO" no arquivo) — ou seja, chama a IA de
// verdade mesmo só para abrir a tela. `PanelKnowledge.vue` (aba
// "Conhecimento" do agente já publicado, o mesmo caminho do roteiro
// 11.08.mjs) reaproveita o MESMO componente MaterialCard.vue — mesmo ícone
// de status, mesma nota/rótulo, mesmo "Reenviar", mesmo contador "X de 30
// materiais" — sem abrir o Construtor. Este vídeo usa esse caminho seguro.
//
// O clique em "Reenviar" dispara reprocessamento real (chama IA para
// reler/revisar o material) — por isso o vídeo aponta para o botão sem
// clicar, mesma regra dos formulários que chamam serviço de fora.
//
// Trajeto: Meus agentes → Sol Atendimento → Conhecimento → 4 materiais com
// parecer diferente (Pronto/Ótima, Revisar, Falha ao ler, confiança baixa).

export const id = '11.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Garante o Sol Atendimento (mesmo fixture de 11.01/11.07/11.08/11.10) e
// quatro materiais de conhecimento com parecer em estados diferentes — para
// a folha de contato mostrar os quatro ícones do artigo.
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

# Material 1 — Pronto / Boa (o mesmo do fixture de 11.08, não mexe nele).
m1 = Autonomia::Agents::Source.find_or_initialize_by(
  account_id: conta.id, autonomia_agent_id: sol.id, source_type: "link",
  reference: "https://www.desnorteada.test/horario-de-atendimento"
)
m1.assign_attributes(
  kind: "knowledge", status: "ready", review_status: "accepted", review_label: "boa",
  confidence: "alta", quality_score: 78,
  review_summary: "Explica o horário comercial e como abrir um sinistro.",
  reviewed_at: Time.current, external_link: m1.reference, metadata: {}
)
m1.save!

# Material 2 — Pronto / Ótima.
m2 = Autonomia::Agents::Source.find_or_initialize_by(
  account_id: conta.id, autonomia_agent_id: sol.id, source_type: "link",
  reference: "https://www.desnorteada.test/politica-de-sinistros"
)
m2.assign_attributes(
  kind: "knowledge", status: "ready", review_status: "accepted", review_label: "otima",
  confidence: "alta", quality_score: 95,
  review_summary: "Cobre o passo a passo do sinistro com prazos claros.",
  reviewed_at: Time.current, external_link: m2.reference, metadata: {}
)
m2.save!

# Material 3 — Revisar (needs_resend): lido, mas conteúdo insuficiente.
m3 = Autonomia::Agents::Source.find_or_initialize_by(
  account_id: conta.id, autonomia_agent_id: sol.id, source_type: "link",
  reference: "https://www.desnorteada.test/perguntas-frequentes"
)
m3.assign_attributes(
  kind: "knowledge", status: "ready", review_status: "needs_resend",
  confidence: "baixa", quality_score: 38,
  review_reason: "Conteúdo muito curto para orientar respostas.",
  reviewed_at: Time.current, external_link: m3.reference, metadata: {}
)
m3.save!

# Material 4 — Falha ao ler (falha técnica de ingestão).
m4 = Autonomia::Agents::Source.find_or_initialize_by(
  account_id: conta.id, autonomia_agent_id: sol.id, source_type: "pdf",
  reference: "Apólice modelo.pdf"
)
m4.assign_attributes(kind: "knowledge", status: "failed", error: "Arquivo protegido por senha.")
m4.save!

# Material 5 — confiança baixa (needs_review): revisora sem credencial.
m5 = Autonomia::Agents::Source.find_or_initialize_by(
  account_id: conta.id, autonomia_agent_id: sol.id, source_type: "link",
  reference: "https://www.desnorteada.test/sobre-a-corretora"
)
m5.assign_attributes(
  kind: "knowledge", status: "ready", review_status: "needs_review",
  confidence: nil, quality_score: nil, review_summary: nil, reviewed_at: nil,
  external_link: m5.reference, metadata: {}
)
m5.save!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ler o parecer de cada material',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
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
    legenda: 'Clique em Conhecimento',
    acao: 'mover e clicar',
    alvo: { texto: 'Conhecimento' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja a nota e o rótulo em Pronto',
    acao: 'parar',
    alvo: { texto: 'Ótima' },
    zoom: 1.8,
    duracaoMs: 1600,
  },
  {
    legenda: 'Leia o resumo escrito pela IA',
    acao: 'parar',
    alvo: { texto: 'Cobre o passo a passo do sinistro com prazos claros.' },
    zoom: 1.5,
    duracaoMs: 1800,
  },
  {
    legenda: 'Revisar: leia o motivo',
    acao: 'parar',
    alvo: { texto: 'Conteúdo muito curto para orientar respostas.' },
    zoom: 1.5,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Reenviar depois de corrigir',
    acao: 'parar',
    alvo: { texto: 'Revisar' },
    zoom: 1.6,
    duracaoMs: 1400,
  },
  {
    legenda: 'Falha ao ler: arquivo ilegível',
    acao: 'parar',
    alvo: { texto: 'Falha ao ler' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Veja o contador de materiais',
    acao: 'parar',
    alvo: { texto: 'Conhecimento', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2000,
  },
];
