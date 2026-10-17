# Prepend em Base::SendOnChannelService (chat#1473, P4): mensagem de WhatsApp com 2 ou mais anexos criada fora da
# API (agente nativo, automação, serviço) fica `failed` com o motivo, e nada é enviado, nem o 1º anexo, para não
# sair pela metade. Só olha o que de fato iria ao canal, e só conta os anexos numa caixa WhatsApp.
# Ver RichMessages::AttachmentLimit.
module RichMessages::AttachmentLimitGuard
  def perform
    return super unless RichMessages::AttachmentLimit.checked?(message) && !invalid_message?

    error = RichMessages::AttachmentLimit.error_for(message.attachments.size)
    return super if error.nil?

    RichMessages.fail!(message, error)
  end
end
