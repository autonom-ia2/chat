# Prepend em Base::SendOnChannelService (chat#1473): mensagem com `rich_message` que não pode sair (tipo
# desconhecido, entrada fora do contrato, combinação proibida, tipo sem versão em texto) não vira texto em
# silêncio. Fica `failed` com o motivo, e nada é enviado. Só olha o que de fato iria ao canal: nota privada,
# mensagem recebida e eco do canal seguem o caminho original.
# Sem `rich_message`, o método original e mais nada.
module RichMessages::SendGuard
  def perform
    return super unless RichMessages.rich?(message)

    error = RichMessages.error_for(message) if outgoing_message? && !invalid_message?
    return super if error.nil?

    RichMessages.fail!(message, error)
  end
end
