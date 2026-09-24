// Roteiro do vídeo de trajeto do artigo 08.04 — "Menções, Participantes e a
// Caixa de Entrada (notificações)". Os três lugares mostram a MESMA
// conversa fictícia deste vídeo por ângulos diferentes: uma nota privada
// menciona "Lia Admin" (@), o que a coloca como participante e gera uma
// notificação — os efeitos reais de uma menção, não simulados com dado
// solto.
//
// O preparar cria isso direto no banco (Mention/ConversationParticipant/
// Notification), sem digitar @ na tela: digitar @ dispara
// Messages::MentionService de verdade, que manda a UserMentionJob (fila,
// não roda em dev sem Sidekiq — lição do P1). Criar os registros já
// resolvidos é o mesmo estado final, sem depender da fila.
//
// Seletores conferidos no código-fonte:
// - "Menções"/"Participantes": rótulos exatos dos links da barra lateral
//   (Sidebar.vue:568/578, conversation.json MENTIONED_CONVERSATIONS/
//   PARTICIPATING_CONVERSATIONS).
// - "Caixa de Entrada": link para a rota 'inbox_view' (settings.json INBOX).
// - item da lista de avisos: `.inbox-card` (InboxList.vue).
//
// Trajeto: Menções → Participantes → Caixa de Entrada → clique no aviso →
// vai direto para a conversa de origem.

export const id = '08.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by!(name: "WhatsApp Comercial")
usuaria = conta.users.find_by!(name: ${JSON.stringify(login.usuarioNome)})
colega = conta.users.find_by!(name: "Bia Vendas")

contato = conta.contacts.find_or_create_by!(name: "Helena Duarte") do |c|
  c.email = "helena-duarte@cliente.test"
  c.phone_number = "+5511990000044"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open)
end
conversa.update!(status: :open)
conversa.messages.where(message_type: :incoming).first ||
  conversa.messages.create!(content: "Preciso de ajuda com a renovacao da minha apolice", message_type: :incoming, account: conta, inbox: inbox, sender: contato)

nota = conversa.messages.find_by(private: true, sender_id: colega.id, sender_type: "User")
nota ||= conversa.messages.create!(content: "@Lia Admin confere esse caso pra mim?", message_type: :outgoing, private: true, account: conta, inbox: inbox, sender: colega)

Mention.find_or_create_by!(conversation: conversa, user: usuaria) { |m| m.mentioned_at = Time.current }
conversa.conversation_participants.find_or_create_by!(user: usuaria)
Notification.find_or_create_by!(account: conta, primary_actor: conversa) do |n|
  n.user = usuaria
  n.notification_type = :conversation_mention
  n.secondary_actor = nota
  n.last_activity_at = Time.current
end
conversa.update_columns(last_activity_at: Time.current)

config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Menções, Participantes e Caixa de Entrada',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique em Menções',
    acao: 'mover e clicar',
    alvo: { texto: 'Menções' },
    aguardarTextoDepois: 'Abertas',
    zoom: 1.5,
  },
  {
    // A conversa deste vídeo não tem responsável — a aba "Minhas" (padrão
    // da tela) não mostra ela. "Todos" cobre qualquer conversa em que você
    // foi mencionado, tenha ou não responsável.
    legenda: 'Veja em Todos, se preciso',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    aguardarTextoDepois: 'Helena Duarte',
    zoom: 1.5,
  },
  {
    legenda: 'Conversas em que você foi citado',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Participantes',
    acao: 'mover e clicar',
    alvo: { texto: 'Participantes' },
    aguardarTextoDepois: 'Abertas',
    zoom: 1.5,
  },
  {
    legenda: 'Veja em Todos, se preciso',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    aguardarTextoDepois: 'Helena Duarte',
    zoom: 1.5,
  },
  {
    legenda: 'Conversas que você acompanha',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Caixa de Entrada',
    acao: 'mover e clicar',
    alvo: { texto: 'Caixa de Entrada' },
    // O card de notificação mostra o remetente da nota ("Bia Vendas: ...")
    // e o avatar do contato, não o nome do contato por extenso — "Mencionado"
    // é o rótulo estável do tipo de notificação.
    aguardarTextoDepois: 'Mencionado',
    zoom: 1.5,
  },
  {
    legenda: 'Cada notificação sua, num só lugar',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique no aviso',
    acao: 'mover e clicar',
    alvo: { seletor: '.inbox-card' },
    zoom: 1.4,
  },
  {
    legenda: 'Vai direto à conversa de origem',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
