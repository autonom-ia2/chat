# Acesso por funil (#1148) no Counter: tag guarda a caixa de cada chave (FunnelCounts conta por id só as restritas).
module Conversations::UnreadCounts::FunnelAccess
  private

  def tag(keys, inbox_id) = keys.each { |key| (@key_inbox ||= {})[key] = inbox_id }
  def funnel_counts = ::Conversations::UnreadCounts::FunnelCounts.new(account: account, scope: funnel_scope)
  def funnel_scope = (@funnel_scope ||= Crm::Access::ConversationScope.new(user: user, account: account, account_user: account_user))
end
