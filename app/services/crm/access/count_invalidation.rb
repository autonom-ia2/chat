# Mudar card ou vínculo muda quem vê a conversa (#1148): os contadores filtrados da lista vencem (cache por versão em
# Conversations::UnreadCounts) e as conversas afetadas são sincronizadas em tempo real (VisibilitySyncJob). Só em conta
# que tem acesso configurado; nas outras nada muda.
module Crm::Access::CountInvalidation
  module_function

  def card_changed!(account_id, conversation_ids = [])
    return unless Crm::Access::AccountFlag.any?(account_id)

    account = Account.find_by(id: account_id)
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).conversation_changed! if account
    ids = Array(conversation_ids).compact.uniq
    Crm::Access::VisibilitySyncJob.perform_later(ids) if ids.any?
  end

  def access_changed!(account_id, user_id)
    account = Account.find_by(id: account_id)
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).user_visibility_changed!(user_id: user_id) if account
  end
end
