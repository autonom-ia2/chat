# chat#1473 (P4, opção A): no WhatsApp só o 1º anexo de uma mensagem saía e os outros sumiam em silêncio (o Cloud e o
# 360dialog usam `attachments.first`; o Híbrido também). Lá, mensagem com 2 ou mais anexos é recusada com motivo: na
# criação pela API (RichMessages::AttachmentLimitCheck, 422) e no envio (RichMessages::AttachmentLimitGuard, `failed`,
# nada sai). O painel já manda um arquivo por mensagem nesses canais e não é afetado.
# Fora daqui: o TikTok já falha com motivo próprio; Instagram, Telegram, Twilio e os demais entregam todos os anexos.
# Envio completo de vários anexos fica para quando houver uso real.
module RichMessages::AttachmentLimit
  ONE_PER_MESSAGE = 'O WhatsApp entrega um anexo por mensagem. Mande cada arquivo numa mensagem separada.'.freeze
  # A caixa `Channel::Whatsapp` cobre os provedores Cloud e 360dialog e o WhatsApp Híbrido (que sai pela mesma caixa).
  # O WhatsApp pela Twilio é outra caixa (`Channel::TwilioSms`) e manda todos os anexos numa requisição.
  CHANNEL_TYPES = %w[Channel::Whatsapp].freeze

  module_function

  # A mensagem passa pela regra: caixa WhatsApp (conferida primeiro, sem consulta) e mensagem de saída comum que vai
  # ao canal. Nota privada fica fora, e modelo também (`template?` ou com `template_params`, que sai por
  # `send_template` sem ler anexos): continuam como eram.
  def checked?(message)
    CHANNEL_TYPES.include?(message.inbox.channel_type) && message.outgoing? && !message.private? &&
      message.additional_attributes.to_h['template_params'].blank?
  end

  # O motivo quando vieram mais anexos do que a caixa entrega numa mensagem; nil quando pode sair.
  def error_for(attachments_count)
    ONE_PER_MESSAGE if attachments_count > 1
  end
end
