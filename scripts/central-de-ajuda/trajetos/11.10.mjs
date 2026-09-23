// Roteiro do vídeo de trajeto do artigo 11.10 — "Quando o agente chama um
// humano e como ajustar a instrução". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json (AGENTS.TUNE).
//
// O motor não tem ação de arrastar (só clicar/digitar/mover/parar), então a
// cena do "Limite de confiança" apenas destaca o controle — sem simular o
// arrasto — e a legenda descreve o gesto, como o artigo pede.
//
// Trajeto: agente → Ajustar → Configurações rápidas (limite de confiança,
// Salvar) → Como você edita (ligar Avançado, escrever instrução, salvar) →
// Histórico da instrução (Restaurar).

export const id = '11.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Garante o Sol Atendimento ativo, em modo Guiado (para a cena mostrar a
// troca para Avançado) — idempotente mesmo depois deste vídeo ligar o
// Avançado e escrever uma instrução manual.
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
  config: { "with_knowledge" => true, "confidence_threshold" => 0.55 }
)
sol.save!
unless Autonomia::Agents::AgentInbox.exists?(autonomia_agent_id: sol.id, inbox_id: inbox.id)
  Autonomia::Agents::Operate::InboxConnector.new(agent: sol, inbox: inbox).perform(connect: true)
end
# Garante pelo menos UMA versão antiga no histórico (além da que este vídeo
# grava ao salvar a instrução), pra "Restaurar" ter o que restaurar. Zera antes
# pra não acumular versão a cada gravação nova.
sol.instruction_versions.delete_all
sol.record_instruction_version!(reason: "manual_edit", created_by: usuaria)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ajustar a instrução do agente',
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
    legenda: 'Abra o agente e clique em Ajustar',
    acao: 'mover e clicar',
    alvo: { texto: 'Sol Atendimento' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Ajustar',
    acao: 'mover e clicar',
    alvo: { texto: 'Ajustar' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja Configurações rápidas',
    acao: 'parar',
    alvo: { texto: 'Configurações rápidas', blocoRolagem: 'center' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Arraste o Limite de confiança',
    acao: 'parar',
    alvo: { texto: 'Limite de confiança' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Salvar alterações',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar alterações' },
    zoom: 1.8,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Vá até Como você edita',
    acao: 'parar',
    alvo: { texto: 'Como você edita', blocoRolagem: 'center' },
    zoom: 1.4,
    duracaoMs: 1400,
  },
  {
    legenda: 'Ligue a chave Avançado',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[role="switch"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva no campo Instrução',
    acao: 'digitar',
    alvo: { seletor: 'textarea' },
    texto: [
      'Responda com tom cordial e objetivo sobre a Corretora Desnorteada.',
    ],
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Salvar instrução',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar instrução' },
    zoom: 1.8,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Role até Histórico da instrução',
    acao: 'parar',
    alvo: { texto: 'Histórico da instrução', blocoRolagem: 'center' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Restaurar numa versão',
    acao: 'mover e clicar',
    alvo: { texto: 'Restaurar' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
];
