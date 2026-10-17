# Mensagem que não é uma pessoa digitando agora no painel: robô (AgentBot), assistente
# (Captain::Assistant) ou envio automático gravado em nome de uma pessoa, pela marca que cada
# um grava. Regra de automação (`Message#human_response?`), follow-up e lembrete do CRM,
# inclusive o composto pela IA (Crm::FollowUps::MessageSender), convite e lembrete de reunião
# do Agendamento (Crm::BookingV2::InviteDeliverer / MeetingReminder), aviso do Agendamento
# (Crm::BookingV2::Notices) e campanha (`additional_attributes`).
#
# Lista única das marcas (#1732): a mesma de Autonomia::Agents::Operate::PessoaDaEquipe
# (#1710), que passa a delegar para cá quando este ramo receber a main.
module Messages::EnvioAutomatico
  REMETENTES_AUTOMATICOS = %w[AgentBot Captain::Assistant].freeze
  MARCAS_DE_ENVIO_AUTOMATICO = %w[automation_rule_id crm_follow_up_id crm_booking_invite_id crm_booking_notice].freeze
  MARCAS_DE_CAMPANHA = %w[campaign_id whatsapp_api_campaign_id].freeze

  module_function

  def automatico?(message)
    REMETENTES_AUTOMATICOS.include?(message.sender_type) || marcado?(message)
  end

  # Envio automático gravado em nome de uma pessoa (remetente User), pela marca.
  def marcado?(message)
    atributos = message.content_attributes.to_h
    extras = message.additional_attributes.to_h
    MARCAS_DE_ENVIO_AUTOMATICO.any? { |marca| atributos[marca].present? } ||
      MARCAS_DE_CAMPANHA.any? { |marca| extras[marca].present? }
  end
end
