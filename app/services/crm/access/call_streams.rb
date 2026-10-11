# Eventos de chamada de voz (EE) iam para o canal da conta inteira, com status e SDP da chamada. Com acesso por funil
# (#1148, parte C), vão para o canal de cada pessoa que pode ver a conversa (membros que o funil deixa ver, mais os
# administradores). Conta sem acesso configurado segue no canal da conta, como antes.
module Crm::Access::CallStreams
  module_function

  def for(conversation)
    return ["account_#{conversation.account_id}"] unless Crm::Access::AccountFlag.any?(conversation.account_id)

    users = Crm::Access::Recipients.inbox_members(conversation).to_a | conversation.account.administrators.to_a
    users.filter_map(&:pubsub_token)
  end
end
