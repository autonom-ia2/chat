// Roteiro do vídeo de trajeto do artigo 13.12 — "Ver o resultado de uma
// campanha de WhatsApp Oficial".
//
// A tela de análises (enterprise/.../campaigns/analytics_controller.rb) lê
// Campaign + CampaignRecipient — sem Sidekiq, nenhuma campanha de verdade
// roda (Whatsapp::OneoffCampaignService só dispara via job agendado). O
// `preparar` cria os dois direto no banco: uma campanha "completed" e um
// CampaignRecipient por contato, com status variado (entregue, lida, falha,
// ignorada) — o mesmo dado que o serviço real produziria, só que sem bater
// no WhatsApp de verdade.
//
// Reaproveita o padrão do 07.05/13.02 para a caixa: Channel::Whatsapp com
// skip_callback (nunca sincroniza com a Meta).

export const id = '13.12';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_CAIXA = 'WhatsApp Campanhas Resultado';
const TELEFONE_CANAL = '5511900000511';
const TITULO_CAMPANHA = 'Renovacao seguro auto - resultado setembro';
const NOME_LABEL_PUBLICO = 'seguro_auto_resultado';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome_caixa = ${JSON.stringify(NOME_CAIXA)}
telefone = ${JSON.stringify(TELEFONE_CANAL)}
titulo_campanha = ${JSON.stringify(TITULO_CAMPANHA)}
nome_label = ${JSON.stringify(NOME_LABEL_PUBLICO)}

# Idempotente: só mexe na caixa/campanha que ESTE roteiro cria.
existente = conta.inboxes.find_by(name: nome_caixa)
if existente
  conta.campaigns.where(inbox_id: existente.id).find_each do |c|
    CampaignRecipient.where(campaign_id: c.id).delete_all
    c.destroy!
  end
  Conversation.where(inbox_id: existente.id).destroy_all
  ContactInbox.where(inbox_id: existente.id).delete_all
  existente.destroy!
end
Channel::Whatsapp.where(phone_number: telefone).delete_all

Channel::Whatsapp.skip_callback(:create, :after, :sync_templates, raise: false)
canal = Channel::Whatsapp.new(
  account: conta,
  phone_number: telefone,
  provider: "default",
  provider_config: { "api_key" => "chave-fake-video" },
  message_templates: [
    {
      "id" => 1,
      "name" => "renovacao_seguro_auto",
      "status" => "approved",
      "category" => "UTILITY",
      "language" => "pt_BR",
      "components" => [
        { "type" => "BODY", "text" => "Olá {{1}}, sua apólice de seguro auto está perto de vencer. Fale com a gente para renovar sem perder desconto." }
      ]
    }
  ],
  message_templates_last_updated: Time.now.utc,
  phone_number_health: {}
)
canal.save!(validate: false)
inbox = Inbox.create!(account: conta, name: nome_caixa, channel: canal)

label = conta.labels.find_or_create_by!(title: nome_label) { |l| l.show_on_sidebar = false }

campanha = conta.campaigns.create!(
  title: titulo_campanha,
  message: "Olá NOME, sua apólice de seguro auto está perto de vencer. Fale com a gente para renovar sem perder desconto.",
  inbox: inbox,
  enabled: true,
  campaign_status: :completed,
  scheduled_at: 2.days.ago,
  started_at: 2.days.ago,
  completed_at: 1.day.ago,
  audience: [{ "id" => label.id, "type" => "Label" }],
  template_params: {
    "name" => "renovacao_seguro_auto",
    "category" => "UTILITY",
    "language" => "pt_BR",
    "processed_params" => { "1" => "NOME" }
  }
)

destinatarios = [
  { nome: "Fernanda Ribas", telefone: "+5511982230301", status: "read" },
  { nome: "Marcelo Andrade", telefone: "+5511982230302", status: "delivered" },
  { nome: "Simone Cardoso", telefone: "+5511982230303", status: "read" },
  { nome: "Rogerio Teles", telefone: "+5511982230304", status: "sent" },
  { nome: "Vanessa Prado", telefone: "+5511982230305", status: "failed" },
  { nome: "Bruno Salviano", telefone: "+5511982230306", status: "skipped" }
]

destinatarios.each_with_index do |d, i|
  contato = conta.contacts.find_or_create_by!(phone_number: d[:telefone]) { |c| c.name = d[:nome] }
  contato.update!(name: d[:nome])

  recipient = CampaignRecipient.create!(
    account: conta,
    campaign: campanha,
    contact: contato,
    inbox: inbox,
    message_content: "Olá #{d[:nome].split(' ').first}, sua apólice de seguro auto está perto de vencer. Fale com a gente para renovar sem perder desconto.",
    status: d[:status] == "skipped" ? :queued : :sent,
    source_id: d[:status] == "skipped" ? nil : "wa-fake-#{campanha.id}-#{i}",
    sent_at: d[:status] == "skipped" ? nil : 2.days.ago
  )

  case d[:status]
  when "delivered"
    recipient.update!(status: :delivered, delivered_at: 2.days.ago + 3.minutes)
  when "read"
    recipient.update!(status: :read, delivered_at: 2.days.ago + 3.minutes, read_at: 2.days.ago + 40.minutes)
  when "failed"
    recipient.update!(status: :failed, failed_at: 2.days.ago + 2.minutes, error_code: "131026", error_title: "Message undeliverable", error_message: "O número de telefone não está registrado no WhatsApp.")
  when "skipped"
    recipient.mark_skipped!("Telefone inválido para envio de WhatsApp")
  end
end

puts "preparo-ok campanha=#{campanha.id}"
`);
}

export const cenas = [
  {
    legenda: 'Ver o resultado de uma campanha de WhatsApp Oficial',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/campaigns/whatsapp`,
    // Não usa o título da campanha: o card aplica CSS "capitalize" nele, e
    // esperarTexto lê innerText (afetado pelo CSS) — comparar com o texto
    // original (minúsculo) nunca bateria. "Concluído" é o rótulo de status,
    // sem transformação, e só aparece quando a campanha já carregou.
    aguardarTexto: 'Concluído',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Encontre a campanha na lista',
    acao: 'parar',
    alvo: { texto: TITULO_CAMPANHA },
    zoom: 1.4,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Ver análises',
    acao: 'mover e clicar',
    // O componente de tooltip troca o atributo title nativo por
    // data-original-title (evita o tooltip duplicado do navegador) — o
    // seletor precisa mirar o atributo de verdade, não `title`.
    alvo: { seletor: '[data-original-title="Ver análises"]' },
    zoom: 2,
    aguardarTextoDepois: 'Entregues',
  },
  {
    legenda: 'Leia os cartões de resultado',
    acao: 'parar',
    alvo: { texto: 'Entregues' },
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    legenda: 'Use as abas para filtrar por status',
    acao: 'mover e clicar',
    alvo: { texto: 'Lida' },
    zoom: 1.6,
  },
  {
    legenda: 'Role para ver contato por contato',
    acao: 'parar',
    alvo: { texto: 'Fernanda Ribas' },
    zoom: 1.4,
    duracaoMs: 2200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1500,
  },
];
