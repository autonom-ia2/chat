// Roteiro do vídeo de trajeto do artigo 08.09 — "Atribuir, assumir da IA,
// resolver e adiar a conversa". O artigo cobre quatro decisões; o vídeo
// mostra as duas mais seguras de reproduzir de forma determinística —
// expandir "Ações da conversa" (onde vive o Agente/Time atribuído) e o
// ciclo Resolver → Reabrir. "Assumir da IA" e "Adiar" exigem estado difícil
// de montar de forma idempotente (um agente de IA respondendo, ou um prazo
// de adiamento) — ficam só no texto do artigo.
//
// Para não mexer nas 4 conversas de teste compartilhadas com os outros
// agentes (cada uma pode estar sendo usada por outro vídeo agora), o
// preparar cria/reaproveita uma conversa fictícia PRÓPRIA deste vídeo
// (contato "Lucas Pereira") e sempre a deixa como a mais recente da conta —
// o painel ordena por atividade mais recente, então ela aparece primeiro na
// aba "Todos" e o seletor genérico `.conversation` (primeiro card) sempre
// acerta ela, sem precisar do id.

export const id = '08.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by!(name: "WhatsApp Comercial")
contato = conta.contacts.find_or_create_by!(name: "Lucas Pereira") do |c|
  c.email = "lucas-pereira@cliente.test"
  c.phone_number = "+5511990000099"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open)
  conversa.messages.create!(content: "Minha apolice venceu, o que eu faco?", message_type: :incoming, account: conta, inbox: inbox, sender: contato)
end
conversa.update!(status: :open, assignee_id: nil, team_id: nil, snoozed_until: nil, last_activity_at: Time.current)
puts "preparo-ok conversa-id=#{conversa.id}"
`);
}

export const cenas = [
  {
    legenda: 'Atribuir, resolver e adiar a conversa',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique na aba Todos',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    zoom: 1.5,
  },
  {
    legenda: 'Abra a conversa',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-ph-user-bold' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra Ações da conversa',
    acao: 'mover e clicar',
    alvo: { texto: 'Ações da conversa' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja Agente e Time atribuído',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Resolver',
    acao: 'mover e clicar',
    alvo: { texto: 'Resolver' },
    zoom: 1.6,
  },
  {
    legenda: 'Conversa resolvida',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Reabrir',
    acao: 'mover e clicar',
    alvo: { texto: 'Reabrir' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
