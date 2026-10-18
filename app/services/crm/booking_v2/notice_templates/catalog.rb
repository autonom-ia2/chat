# Os modelos de aviso v1 da plataforma (#1272): um por aviso, nome estável, pt_BR, corpo com {{1}} primeiro nome, {{2}}
# dia e hora e {{3}} link de gestão (onde fica o "Parar avisos"), igual ao que o envio preenche (`Notices::Delivery`).
#
# O botão que os criava na Meta saiu em #1612 (postava sem o `Whatsapp::Templates::Garantir` e sem a autorização do
# dono, #1585); os novos são os v2 (`Whatsapp::Templates::Finalidades::Agendamento`). Os v1 que as contas já têm
# continuam valendo, por isso o catálogo fica: os nomes protegem esses modelos na tela de Modelos
# (`Whatsapp::Templates::SystemTemplates`) e a sugestão da IA os reconhece (`NoticeTemplates::Suggester`).
class Crm::BookingV2::NoticeTemplates::Catalog
  LANGUAGE = 'pt_BR'.freeze
  LINK_LINE = 'Para confirmar, mudar, cancelar ou parar estes avisos, acesse {{3}} e escolha a opção.'.freeze
  TEMPLATES = {
    'booked' => { name: 'agendamento_ao_marcar_v1', text: "Olá, {{1}}! Seu horário está marcado para {{2}}.\n\n#{LINK_LINE}" },
    'rescheduled' => { name: 'agendamento_horario_mudou_v1', text: "Olá, {{1}}! Seu horário mudou para {{2}}.\n\n#{LINK_LINE}" },
    'day_before' => { name: 'agendamento_1_dia_antes_v1', text: "Olá, {{1}}! Lembrete: seu horário é amanhã, {{2}}.\n\n#{LINK_LINE}" },
    'hour_before' => { name: 'agendamento_1_hora_antes_v1',
                       text: "Olá, {{1}}! Lembrete: seu horário começa em 1 hora ({{2}}).\n\n#{LINK_LINE}" }
  }.freeze

  def self.kinds
    TEMPLATES.keys
  end

  # Os nomes dos modelos da plataforma (protegidos na tela de Modelos, #1330).
  def self.names
    kinds.map { |kind| name_for(kind) }
  end

  def self.name_for(kind)
    TEMPLATES.fetch(kind.to_s)[:name]
  end

  def self.body_for(kind)
    TEMPLATES.fetch(kind.to_s)[:text]
  end

  # A lista sincronizada da caixa (a coluna nasce `{}`: sem lista, nenhum modelo).
  def self.templates_of(inbox)
    list = inbox&.channel.try(:message_templates)
    list.is_a?(Array) ? list.select { |item| item.is_a?(Hash) } : []
  end
end
