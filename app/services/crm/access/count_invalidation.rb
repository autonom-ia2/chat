# Os contadores filtrados da lista de conversas ficam em cache por versão (Conversations::UnreadCounts). Com acesso por
# funil (#1148), mudar card ou vínculo muda quem vê a conversa: o cache vence. Só em conta que tem acesso configurado;
# nas outras nada muda.
module Crm::Access::CountInvalidation
  module_function

  def card_changed!(account_id)
    return unless Crm::InboxAgentAccess.exists?(account_id: account_id)

    account = Account.find_by(id: account_id)
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).conversation_changed! if account
  end

  def access_changed!(account_id, user_id)
    account = Account.find_by(id: account_id)
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).user_visibility_changed!(user_id: user_id) if account
  end
end
