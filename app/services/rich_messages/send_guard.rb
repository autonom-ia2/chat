# Prepend em Base::SendOnChannelService (chat#1473): `rich_message` inválido (tipo desconhecido, rótulo, link ou
# corpo fora do contrato) não vira texto em silêncio. A mensagem fica `failed` com o motivo, e nada é enviado.
module RichMessages::SendGuard
  def perform
    error = RichMessages.error_for(message)
    return super if error.nil?

    message.update!(status: :failed, external_error: error)
  end
end
