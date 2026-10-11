# Mudar card ou vínculo muda quem vê a conversa (#1148): os contadores filtrados da lista vencem (cache por versão em
# Conversations::UnreadCounts) e as conversas afetadas são sincronizadas em tempo real (VisibilitySyncJob). Só em conta
# que tem acesso configurado; nas outras nada muda.
module Crm::Access::CountInvalidation
  # Um vínculo dispara até três avisos (o do vínculo, o do card e o do ConversationLinker). Enquanto a conversa tem
  # sincronização na fila, os outros avisos não enfileiram de novo: o job lê o estado na hora em que roda e solta a marca
  # antes de ler, então nenhuma mudança se perde. O prazo só vale se o job se perder.
  PENDING_KEY = 'crm:access:sync_pending:%<conversation_id>s'.freeze
  PENDING_TTL = 5.minutes.to_i

  module_function

  def card_changed!(account_id, conversation_ids = [])
    return unless Crm::Access::AccountFlag.any?(account_id)

    account = Account.find_by(id: account_id)
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).conversation_changed! if account
    enqueue_sync(Array(conversation_ids).compact.uniq)
  end

  # Se o job não entrar na fila, a marca sai junto: senão as próximas mudanças ficariam sem sincronizar até o prazo.
  def enqueue_sync(conversation_ids)
    ids = conversation_ids.select { |id| Redis::Alfred.set(pending_key(id), '1', nx: true, ex: PENDING_TTL) }
    Crm::Access::VisibilitySyncJob.perform_later(ids) if ids.any?
  rescue StandardError
    sync_started!(ids) if ids
    raise
  end

  # O job chama antes de ler as conversas: mudança que chegar depois enfileira outra sincronização.
  def sync_started!(conversation_ids)
    Array(conversation_ids).each { |id| Redis::Alfred.delete(pending_key(id)) }
  end

  def pending_key(conversation_id)
    format(PENDING_KEY, conversation_id: conversation_id)
  end

  def access_changed!(account_id, user_id)
    account = Account.find_by(id: account_id)
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).user_visibility_changed!(user_id: user_id) if account
  end
end
