# Acesso por funil (#1148): os conjuntos de não lidas em Redis são por caixa e não conhecem o funil. Quem tem restrição
# conta os ids dos conjuntos que o escopo da lista deixa ver (Crm::Access::ConversationScope). Os conjuntos são só de
# conversas não lidas, então a consulta é pequena. Quem não tem restrição segue no SCARD do Counter.
class Conversations::UnreadCounts::FunnelCounts
  def initialize(account:, scope:)
    @account = account
    @scope = scope
  end

  def counts_for(keys_by_id)
    ids_by_key = ::Conversations::UnreadCounts::Store.members_for_keys(keys_by_id.values.flatten.uniq)
    candidates = ids_by_key.values.flatten.uniq
    visible = @scope.apply(@account.conversations.where(id: candidates)).pluck(:id).to_set

    keys_by_id.each_with_object({}) do |(id, keys), result|
      count = keys.sum { |key| ids_by_key.fetch(key, []).count { |conversation_id| visible.include?(conversation_id) } }
      result[id.to_s] = count if count.positive?
    end
  end
end
