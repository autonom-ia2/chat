// Roteiro do vídeo de trajeto do artigo 11.08 — "Aba Conhecimento e aba
// Canais". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json (AGENTS.KNOWLEDGE e
// AGENTS.CHANNELS) e em PanelKnowledge.vue/PanelChannels.vue.
//
// Trajeto: Meus agentes → Sol Atendimento → Conhecimento → Adicionar
// conhecimento → Enviar um arquivo → Cancelar → material existente →
// Sincronizar novamente → Canais → Conectar um canal disponível.

export const id = '11.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Garante o Sol Atendimento (ativo, externo, com base) com 1 material de
// conhecimento aprovado, conectado só à inbox "Instagram Loja" — sem
// conectar as outras, para a aba Canais mostrar caixas disponíveis de
// verdade neste vídeo.
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

# Desconecta qualquer outra inbox que este agente tenha ganhado em execuções
# anteriores (ex.: de 11.08 clicando Conectar), pra Canais disponíveis sempre
# mostrar pelo menos uma caixa livre.
Autonomia::Agents::AgentInbox.where(autonomia_agent_id: sol.id).where.not(inbox_id: inbox.id).each do |ai|
  Autonomia::Agents::Operate::InboxConnector.new(agent: sol, inbox: ai.inbox).perform(connect: false)
end

fonte = Autonomia::Agents::Source.find_or_initialize_by(
  account_id: conta.id, autonomia_agent_id: sol.id, source_type: "link",
  reference: "https://www.desnorteada.test/horario-de-atendimento"
)
fonte.assign_attributes(
  kind: "knowledge",
  status: "ready",
  review_status: "accepted",
  review_label: "boa",
  external_link: "https://www.desnorteada.test/horario-de-atendimento",
  metadata: {}
)
fonte.save!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Gerenciar conhecimento e canais',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2000,
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
    legenda: 'Clique em Adicionar conhecimento',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar conhecimento' },
    zoom: 1.6,
  },
  {
    legenda: 'Troque para Enviar um arquivo',
    acao: 'mover e clicar',
    alvo: { texto: 'Enviar um arquivo' },
    zoom: 1.6,
  },
  {
    // A caixa (SourceAddDialog) não tem botão de cancelar no rodapé — fecha
    // clicando fora dela (OnClickOutside), então o alvo do clique é o título
    // da aba, atrás da caixa.
    legenda: 'Feche sem enviar',
    acao: 'mover e clicar',
    alvo: { seletor: 'h1, h2' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja o material já aprovado',
    acao: 'parar',
    alvo: { texto: 'Pronto', blocoRolagem: 'center' },
    zoom: 1.5,
    duracaoMs: 1200,
  },
  {
    // O ícone de Reenviar/Sincronizar só aparece em material com falha ou
    // revisão pendente — o material deste vídeo já está aprovado, então a
    // cena mostra o ícone de remover (o outro controle do card) sem
    // confirmar a remoção.
    legenda: 'Clique no ícone de remover',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-trash-2' },
    zoom: 1.8,
  },
  {
    legenda: 'Confirme em Remover este material?',
    acao: 'parar',
    alvo: { texto: 'Remover este material?' },
    zoom: 1.5,
    duracaoMs: 1200,
  },
  {
    legenda: 'Feche sem remover',
    acao: 'mover e clicar',
    alvo: { seletor: 'h1, h2' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Canais',
    acao: 'mover e clicar',
    alvo: { texto: 'Canais' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja Canais disponíveis',
    acao: 'parar',
    alvo: { texto: 'Canais disponíveis' },
    zoom: 1.5,
    duracaoMs: 1000,
  },
  {
    legenda: 'Clique em Conectar numa caixa livre',
    acao: 'mover e clicar',
    alvo: { texto: 'Conectar' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
];
