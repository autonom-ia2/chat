// Roteiro do vídeo de trajeto do artigo 11.09 — "Aba Desempenho e
// configurações rápidas". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json
// (AGENTS.PERFORMANCE, AGENTS.TUNE).
//
// ACHADO DE PRODUTO: o campo "Atuação" (e também "Tom" e "Transferir para um
// humano") em Ajustar usa `dashboard/components-next/select/Select.vue`, que
// renderiza um `<select>` HTML nativo (linha 50 do componente) — a regra do
// Rodrigo (18/09/2026, Bio #81) proíbe `<select>` nativo em UI de produto.
// Este vídeo usa a ação `selecionar` do motor para operar o campo Atuação
// (o primeiro `<select>` da aba); os demais campos nativos só aparecem na
// tela, sem seleção, para não precisar escolher entre vários `<select>`
// indistinguíveis por seletor CSS.
//
// Sem dados de verdade (sem Sidekiq, sem conversa real no dev), a aba
// Desempenho fica vazia — o preparar grava eventos de agente e conversas
// fictícias diretamente no banco (Autonomia::Agents::AgentEvent +
// ReportingEvent) para os cinco números, o gráfico Atividade e os
// resultados por conversa aparecerem preenchidos.
//
// Trajeto: Meus agentes → Sol Atendimento → Desempenho (números, resultados
// por conversa, motivos de transferência) → Ajustar (Configurações rápidas,
// Atuação, Primeira mensagem, Salvar alterações).

export const id = '11.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

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

# Zera o que este vídeo cria em execuções anteriores (idempotente).
Autonomia::Agents::AgentEvent.where(autonomia_agent_id: sol.id).delete_all
convas_antigas = Conversation.where(account_id: conta.id, inbox_id: inbox.id)
                              .where("additional_attributes->>'gerado_para' = ?", "11.09")
ReportingEvent.where(conversation_id: convas_antigas.select(:id)).delete_all
Message.where(conversation_id: convas_antigas.select(:id)).delete_all
convas_antigas.destroy_all

def cria_conversa_1109(conta, inbox, nome, email, criada_em)
  contato = conta.contacts.find_or_create_by!(email: email) { |c| c.name = nome }
  contato.update!(name: nome)
  contact_inbox = ContactInbox.find_or_create_by!(contact_id: contato.id, inbox_id: inbox.id) do |ci|
    ci.source_id = SecureRandom.uuid
  end
  conversa = Conversation.create!(
    account_id: conta.id, inbox_id: inbox.id, contact_id: contato.id,
    contact_inbox_id: contact_inbox.id, status: :open,
    additional_attributes: { "gerado_para" => "11.09" }
  )
  conversa.update_columns(created_at: criada_em, updated_at: criada_em)
  conversa
end

agora = Time.current

respondidas = [
  { nome: "Marcia Andrade", email: "marcia.andrade@desnorteada.test", confianca: 0.92, conhecimento: true, dias: 0 },
  { nome: "Paulo Nogueira", email: "paulo.nogueira@desnorteada.test", confianca: 0.88, conhecimento: true, dias: 1 },
  { nome: "Iris Cavalcante", email: "iris.cavalcante@desnorteada.test", confianca: 0.75, conhecimento: false, dias: 1 },
  { nome: "Renato Gusmao", email: "renato.gusmao@desnorteada.test", confianca: 0.81, conhecimento: true, dias: 2 },
  { nome: "Beatriz Amorim", email: "beatriz.amorim@desnorteada.test", confianca: 0.69, conhecimento: false, dias: 3 },
  { nome: "Diego Serpa", email: "diego.serpa@desnorteada.test", confianca: 0.90, conhecimento: true, dias: 4 },
]

respondidas.each_with_index do |dados, indice|
  criada_em = agora - dados[:dias].days - 2.hours
  conversa = cria_conversa_1109(conta, inbox, dados[:nome], dados[:email], criada_em)
  respondida_em = criada_em + 4.minutes
  Autonomia::Agents::AgentEvent.create!(
    account_id: conta.id, autonomia_agent_id: sol.id, conversation_id: conversa.id,
    event_type: :replied, confidence: dados[:confianca], answered_from_knowledge: dados[:conhecimento],
    created_at: respondida_em
  )
  next unless indice < 4

  resolvida_em = respondida_em + 6.minutes
  ReportingEvent.create!(
    name: "conversation_resolved",
    value: (resolvida_em - conversa.created_at).to_i,
    value_in_business_hours: (resolvida_em - conversa.created_at).to_i,
    account_id: conta.id, inbox_id: inbox.id, conversation_id: conversa.id,
    event_start_time: conversa.created_at, event_end_time: resolvida_em
  )
  conversa.update_columns(status: Conversation.statuses[:resolved])
end

transferidas = [
  { nome: "Heitor Bandeira", email: "heitor.bandeira@desnorteada.test", motivo: "missing_knowledge", dias: 0 },
  { nome: "Cassia Monteiro", email: "cassia.monteiro@desnorteada.test", motivo: "low_confidence", dias: 2 },
]

transferidas.each do |dados|
  criada_em = agora - dados[:dias].days - 3.hours
  conversa = cria_conversa_1109(conta, inbox, dados[:nome], dados[:email], criada_em)
  Autonomia::Agents::AgentEvent.create!(
    account_id: conta.id, autonomia_agent_id: sol.id, conversation_id: conversa.id,
    event_type: :handed_off, handoff_reason: dados[:motivo], created_at: criada_em + 3.minutes
  )
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Desempenho e configurações rápidas',
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
    legenda: 'Clique em Desempenho',
    acao: 'mover e clicar',
    alvo: { texto: 'Desempenho' },
    aguardarTextoDepois: 'Conversas atendidas',
    zoom: 1.8,
  },
  {
    legenda: 'Leia os cinco números',
    acao: 'parar',
    alvo: { texto: 'Taxa de transferência' },
    zoom: 1.5,
    duracaoMs: 1800,
  },
  {
    legenda: 'Role até Resultados por conversa',
    acao: 'parar',
    alvo: { texto: 'Resultados por conversa', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Veja os motivos de transferência',
    acao: 'parar',
    alvo: { texto: 'Principais motivos de transferência', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Ajustar',
    acao: 'mover e clicar',
    alvo: { texto: 'Ajustar' },
    zoom: 1.8,
  },
  {
    legenda: 'Vá até Configurações rápidas',
    acao: 'parar',
    alvo: { texto: 'Configurações rápidas', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1200,
  },
  {
    legenda: 'Escolha a Atuação',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="Atuação"]' },
    valor: 'external',
    zoom: 1.8,
  },
  {
    legenda: 'Escreva a Primeira mensagem',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Olá! Como posso ajudar você hoje?"]' },
    limparAntes: true,
    texto: ['Oi! Sou o assistente da Corretora Desnorteada.'],
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Salvar alterações',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar alterações' },
    aguardarTextoDepois: 'salvas',
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
