# Acesso por funil (#1148): os conjuntos de não lidas em Redis são por caixa e não conhecem o funil. Para quem tem
# restrição, as chaves das caixas livres seguem no SCARD (o escopo diz que tudo nelas é visível); só as chaves das caixas
# restritas são lidas por id (SMEMBERS) e filtradas pelo escopo da lista (Crm::Access::ConversationScope).
class Conversations::UnreadCounts::FunnelCounts
  BATCH = 1000

  def initialize(account:, scope:)
    @account = account
    @scope = scope
  end

  # key_inbox: a caixa de cada chave, montada pelo Counter.
  def counts_for(keys_by_id, key_inbox)
    restricted = @scope.restricted_inbox_ids
    keys = keys_by_id.values.flatten.uniq
    restricted_keys, free_keys = keys.partition { |key| restricted.include?(key_inbox.to_h[key]) }

    counts_by_key = ::Conversations::UnreadCounts::Store.counts_for_keys(free_keys)
    counts_by_key.merge!(visible_counts(restricted_keys))

    keys_by_id.each_with_object({}) do |(id, id_keys), result|
      count = id_keys.sum { |key| counts_by_key[key].to_i }
      result[id.to_s] = count if count.positive?
    end
  end

  private

  def visible_counts(keys)
    ids_by_key = ::Conversations::UnreadCounts::Store.members_for_keys(keys)
    # Em lotes: os conjuntos são de não lidas, mas numa conta grande podem passar de milhares (#1148, parte C).
    visible = ids_by_key.values.flatten.uniq.each_slice(BATCH).with_object(Set.new) do |ids, set|
      set.merge(@scope.apply(@account.conversations.where(id: ids)).pluck(:id))
    end
    ids_by_key.transform_values { |ids| ids.count { |conversation_id| visible.include?(conversation_id) } }
  end
end
