# Modelos de aviso que a plataforma já tem escritos para criar na Meta com um toque (#1272): um por aviso, nome estável
# (o mesmo em toda caixa: é ele que torna a criação idempotente), categoria utility, pt_BR. Corpo com {{1}} primeiro
# nome, {{2}} dia e hora e {{3}} link de gestão (onde fica o "Parar avisos"), igual ao que o envio preenche
# (`Notices::Delivery`). A Meta recusa variável no começo ou no fim do corpo: por isso o texto termina depois do {{3}}.
#
# O que a Meta diz do pedido (em aprovação, aprovado, recusado) vem da lista de modelos da caixa
# (`channel.message_templates`): o `Creator` põe o modelo nela como PENDING ao criar, e a sincronia da caixa traz o status
# que a Meta der depois. O "enviando" e a falha ao criar ficam nos metadados da página (`Requests`). Sem coluna nova.
class Crm::BookingV2::NoticeTemplates::Catalog
  LANGUAGE = 'pt_BR'.freeze
  CATEGORY = 'UTILITY'.freeze
  LINK_LINE = 'Para confirmar, mudar, cancelar ou parar estes avisos, acesse {{3}} e escolha a opção.'.freeze
  TEMPLATES = {
    'booked' => { name: 'agendamento_ao_marcar_v1', text: "Olá, {{1}}! Seu horário está marcado para {{2}}.\n\n#{LINK_LINE}" },
    'rescheduled' => { name: 'agendamento_horario_mudou_v1', text: "Olá, {{1}}! Seu horário mudou para {{2}}.\n\n#{LINK_LINE}" },
    'day_before' => { name: 'agendamento_1_dia_antes_v1', text: "Olá, {{1}}! Lembrete: seu horário é amanhã, {{2}}.\n\n#{LINK_LINE}" },
    'hour_before' => { name: 'agendamento_1_hora_antes_v1',
                       text: "Olá, {{1}}! Lembrete: seu horário começa em 1 hora ({{2}}).\n\n#{LINK_LINE}" }
  }.freeze
  # Exemplo que a Meta pede para cada variável do corpo.
  EXAMPLE_NAME = 'Ana'.freeze
  EXAMPLE_WHEN = '14/10 às 15:00'.freeze
  STATUSES = { 'APPROVED' => 'approved', 'REJECTED' => 'rejected', 'DISABLED' => 'rejected', 'PAUSED' => 'rejected' }.freeze

  def self.kinds
    TEMPLATES.keys
  end

  def self.name_for(kind)
    TEMPLATES.fetch(kind.to_s)[:name]
  end

  def self.body_for(kind)
    TEMPLATES.fetch(kind.to_s)[:text]
  end

  def self.example_link
    "#{Crm::BookingInvite.base_url.presence || 'https://exemplo.com.br'}/b/AB3K9QXZ"
  end

  # A lista sincronizada da caixa (a coluna nasce `{}`: sem lista, nenhum modelo).
  def self.templates_of(inbox)
    list = inbox&.channel.try(:message_templates)
    list.is_a?(Array) ? list.select { |item| item.is_a?(Hash) } : []
  end

  # O modelo da plataforma para o aviso, se já está na lista da caixa (qualquer status).
  def self.listed(inbox, kind)
    name = name_for(kind)
    templates_of(inbox).find { |item| item['name'] == name && item['language'].to_s.casecmp?(LANGUAGE) }
  end

  # O que a Meta diz dos modelos da plataforma já na caixa: { "<aviso>" => { state:, reason:, name:, language: } },
  # state "pending" (em aprovação), "approved" ou "rejected" (com o motivo da Meta).
  def self.meta_states(inbox)
    kinds.each_with_object({}) do |kind, states|
      found = listed(inbox, kind)
      next unless found

      state = STATUSES.fetch(found['status'].to_s.upcase, 'pending')
      states[kind] = { 'state' => state, 'reason' => state == 'rejected' ? rejected_reason(inbox, found) : nil,
                       'name' => found['name'], 'language' => found['language'] }
    end
  end

  def self.rejected_reason(inbox, template)
    reason = template['rejected_reason'].to_s
    reason.blank? || reason.casecmp?('NONE') ? text(inbox.account, 'meta_rejected') : reason
  end

  def self.text(account, key)
    I18n.t("crm.booking_v2.notice_templates.#{key}", locale: Crm::BookingV2::Notices::Text.locale(account))
  end
end
