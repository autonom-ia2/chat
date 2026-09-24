// Roteiro do vídeo de trajeto do artigo 14.09 — "Relatórios do Bot e de
// SLA". Dois relatórios distintos: Robôs (mostra o estado real, zerado —
// nenhuma caixa desta conta de teste tem bot ativo, e criar um bot só para
// isto seria mexer numa integração que o vídeo não devia tocar) e SLA
// (com uma violação de verdade, criada pelo preparar, para a tabela não
// ficar vazia).
//
// Seletores conferidos no código-fonte:
// - "Relatórios do Bot" (BOT_REPORTS.HEADER) / "Relatórios SLA"
//   (SLA_REPORTS.HEADER).
// - "Adicionar filtro" (SLA_REPORTS.DROPDOWN.ADD_FIlTER — grafia da chave,
//   não do texto).
// - "Ver detalhes" no fim de cada linha da tabela de SLA.
//
// Trajeto: Relatórios → Robôs (lê os números) → Relatórios → SLA (lê Taxa
// de acerto/Número de Erros → Adicionar filtro → abre uma linha).

export const id = '14.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_POLITICA = 'Resposta em 4 horas';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by!(name: "WhatsApp Comercial")
usuaria = conta.users.find_by!(name: ${JSON.stringify(login.usuarioNome)})

politica = conta.sla_policies.find_or_create_by!(name: ${JSON.stringify(NOME_POLITICA)}) do |p|
  p.description = "Primeira resposta em até 4 horas"
  p.first_response_time_threshold = 4.hours.to_i
end

contato = conta.contacts.find_or_create_by!(name: "Juliana Alves") do |c|
  c.email = "juliana-alves@cliente.test"
  c.phone_number = "+5511990000022"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open, assignee: usuaria)
end
conversa.update!(status: :open, assignee: usuaria, sla_policy_id: politica.id)
msg = conversa.messages.where(message_type: :incoming).first
if msg.nil?
  msg = conversa.messages.create!(content: "Ainda aguardo retorno sobre o sinistro do meu carro", message_type: :incoming, account: conta, inbox: inbox, sender: contato)
end
msg.update_columns(created_at: 6.hours.ago, updated_at: 6.hours.ago)

aplicada = conta.applied_slas.find_or_create_by!(sla_policy: politica, conversation: conversa)
aplicada.update!(sla_status: :missed)
SlaEvent.find_or_create_by!(account: conta, applied_sla: aplicada, conversation: conversa, inbox: inbox, sla_policy: politica, event_type: :frt) do |e|
  e.meta = {}
end
conversa.update_columns(last_activity_at: Time.current)

config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Relatórios do Bot e de SLA',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Relatórios, Robôs',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/bot`,
    aguardarTexto: 'Relatórios do Bot',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Leia Nº de Conversas e a Taxa de entrega',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Abra Relatórios, SLA',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/sla`,
    aguardarTexto: 'Relatórios SLA',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Leia Taxa de acerto e Número de Erros',
    acao: 'parar',
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
    legenda: 'Restrinja por agente, caixa, time ou etiqueta',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1600,
  },
  {
    legenda: 'Abra uma linha da tabela',
    acao: 'mover e clicar',
    alvo: { texto: 'Ver detalhes' },
    zoom: 1.5,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
