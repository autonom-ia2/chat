// Roteiro do vídeo de trajeto do artigo 08.06 — "Quando o produto bloqueia
// a resposta". Para mostrar o bloqueio de verdade (não só descrever), o
// preparar monta uma caixa de entrada Channel::Api PRÓPRIA deste vídeo
// ("WhatsApp Pós-venda" — não é nenhuma das 4 caixas compartilhadas com os
// outros agentes) com `agent_reply_time_window` de 1 hora
// (app/services/conversations/message_window_service.rb:36-39) e uma
// conversa cuja última mensagem do cliente tem 3 horas — fora da janela,
// então `can_reply?` (app/models/conversation.rb:153) fica falso e a
// plataforma mostra o aviso de bloqueio e troca sozinha para a aba Mensagem
// Privada (app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue).
//
// Trajeto: tela de Conversas → aba Todos → abre a conversa bloqueada (já
// abre na aba Mensagem Privada, com o aviso) → clique em Responder para ver
// a caixa travada.

export const id = '08.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by(name: "WhatsApp Pós-venda")
if inbox.nil?
  canal = Channel::Api.create!(account: conta, webhook_url: "https://demo.invalid/webhook")
  inbox = Inbox.create!(channel: canal, account: conta, name: "WhatsApp Pós-venda")
end
inbox.channel.update!(additional_attributes: { "agent_reply_time_window" => "1" })

contato = conta.contacts.find_or_create_by!(name: "Renata Souza") do |c|
  c.email = "renata-souza@cliente.test"
  c.phone_number = "+5511990000077"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open)
end
conversa.update!(status: :open, assignee_id: nil, team_id: nil, snoozed_until: nil)

msg = conversa.messages.where(message_type: :incoming).first
if msg.nil?
  msg = conversa.messages.create!(content: "Ainda não recebi retorno sobre o pagamento da minha apólice", message_type: :incoming, account: conta, inbox: inbox, sender: contato)
end
msg.update_columns(created_at: 3.hours.ago, updated_at: 3.hours.ago)
conversa.update_columns(last_activity_at: Time.current)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Quando o produto bloqueia a resposta',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
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
    legenda: 'Leia o aviso acima da caixa',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    legenda: 'Volte para a aba Responder',
    acao: 'mover e clicar',
    alvo: { texto: 'Responder' },
    zoom: 1.6,
  },
  {
    legenda: 'A caixa de resposta está bloqueada',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];
