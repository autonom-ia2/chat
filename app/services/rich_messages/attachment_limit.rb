# chat#1473 (P4, opção A): no WhatsApp só o 1º anexo de uma mensagem saía e os outros sumiam em silêncio (o Cloud e o
# 360dialog usam `attachments.first`; o Híbrido também). Lá, mensagem com 2 ou mais anexos é recusada com motivo: na
# criação pela API (RichMessages::AttachmentLimitCheck, 422) e no envio (RichMessages::AttachmentLimitGuard, `failed`,
# nada sai). O painel já manda um arquivo por mensagem nesses canais e não é afetado.
# Fora daqui: o TikTok já falha com motivo próprio; Instagram, Telegram, Twilio e os demais entregam todos os anexos.
# Envio completo de vários anexos (uma chamada por anexo) fica para quando houver uso real.
module RichMessages::AttachmentLimit
  ONE_PER_MESSAGE = 'O WhatsApp entrega um anexo por mensagem. Mande cada arquivo numa mensagem separada.'.freeze
  # A caixa `Channel::Whatsapp` cobre os provedores Cloud e 360dialog e o WhatsApp Híbrido (que sai pela mesma caixa).
  # O WhatsApp pela Twilio é outra caixa (`Channel::TwilioSms`) e manda todos os anexos numa requisição.
  CHANNEL_TYPES = %w[Channel::Whatsapp].freeze

  module_function

  # O motivo quando a caixa entrega um anexo por mensagem e vieram mais; nil quando pode sair.
  def error_for(inbox, attachments_count)
    ONE_PER_MESSAGE if attachments_count > 1 && CHANNEL_TYPES.include?(inbox.channel_type)
  end
end
