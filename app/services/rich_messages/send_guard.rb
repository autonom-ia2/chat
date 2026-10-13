# Prepend em Base::SendOnChannelService (chat#1473): mensagem com `rich_message` que não pode sair (tipo
# desconhecido, entrada fora do contrato, combinação proibida, tipo sem versão em texto) não vira texto em
# silêncio. Fica `failed` com o motivo, e nada é enviado. Só olha o que de fato iria ao canal: nota privada,
# mensagem recebida e eco do canal seguem o caminho original.
module RichMessages::SendGuard
  def perform
    error = RichMessages.error_for(message) if outgoing_message? && !invalid_message?
    return super if error.nil?

    message.update!(status: :failed, external_error: error)
  end
end
