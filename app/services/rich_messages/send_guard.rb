# Prepend em Base::SendOnChannelService (chat#1473): mensagem com `rich_message` que não pode sair (tipo
# desconhecido, entrada fora do contrato, combinação proibida, tipo sem versão em texto) não vira texto em
# silêncio. Fica `failed` com o motivo, e nada é enviado. Só olha o que de fato iria ao canal: nota privada,
# mensagem recebida e eco do canal seguem o caminho original.
# Depois do envio, fora do WhatsApp oficial o formato saiu como texto: a mensagem ganha a marca (chat#1555).
# No WhatsApp oficial quem marca é o WhatsApp Híbrido, quando a mensagem sai pelo WAHA.
# Sem `rich_message`, o método original e mais nada.
module RichMessages::SendGuard
  def perform
    return super unless RichMessages.rich?(message)
    return super unless outgoing_message? && !invalid_message?

    error = RichMessages.error_for(message)
    return RichMessages.fail!(message, error) if error

    result = super
    RichMessages.mark_sent_as_text!(message) unless RichMessages.whatsapp_cloud?(message.inbox)
    result
  end
end
