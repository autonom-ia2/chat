// Roteiro do vídeo de trajeto do artigo 14.08 — "CSAT: indicadores, filtros
// e tabela". A conta de teste não tinha nenhuma resposta de CSAT — sem
// dado, a tabela mostra só o estado vazio ("Ainda não há respostas"), o que
// não ajudaria a mostrar "role até a tabela para ver o comentário do
// cliente". O preparar por isso semeia (idempotente) UMA conversa e
// resposta de CSAT próprias deste vídeo (contato "Fernanda Lima"), com
// conteúdo de corretora de seguros — não uma conversa "de teste".
//
// Trajeto: Relatórios → CSAT → leia os três cartões → Adicionar filtro →
// role até a tabela de respostas.

export const id = '14.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
a = Account.find(${login.contaId})
inbox = a.inboxes.find_by!(name: "WhatsApp Comercial")
agente = a.users.find_by!(name: "Bia Vendas")
contato = a.contacts.find_or_create_by!(name: "Fernanda Lima") do |c|
  c.email = "fernanda-lima@cliente.test"
  c.phone_number = "+5511990000088"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = a.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = a.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :resolved, assignee_id: agente.id)
end
conversa.update!(status: :resolved, assignee_id: agente.id)

msg_in = conversa.messages.where(message_type: :incoming).first
msg_in ||= conversa.messages.create!(content: "Preciso de uma segunda via do boleto da apólice", message_type: :incoming, account: a, inbox: inbox, sender: contato)

msg_out = conversa.messages.where(message_type: :outgoing).first
msg_out ||= conversa.messages.create!(content: "Aqui está a segunda via, qualquer coisa é só chamar", message_type: :outgoing, account: a, inbox: inbox, sender: agente)

csat = a.csat_survey_responses.find_by(conversation_id: conversa.id)
if csat.nil?
  a.csat_survey_responses.create!(conversation: conversa, contact: contato, message: msg_out, rating: 5, feedback_message: "Atendimento rápido, resolveu meu problema com a apólice", assigned_agent_id: agente.id)
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'CSAT: indicadores, filtros e tabela',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Relatórios, CSAT',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/csat`,
    aguardarTexto: 'Total de respostas',
    zoom: 1,
    duracaoMs: 1600,
  },
  {
    legenda: 'Leia os três cartões',
    acao: 'parar',
    alvo: { texto: 'Total de respostas' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Veja a Pontuação de satisfação',
    acao: 'parar',
    alvo: { texto: 'Pontuação de satisfação' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Adicionar filtro',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar filtro' },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha Agente, Caixa ou Time',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Role até a tabela de respostas',
    acao: 'parar',
    alvo: { texto: 'Fernanda Lima', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];
