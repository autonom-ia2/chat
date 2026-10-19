# O "lido" da conversa num lugar só (#1870). É o mesmo efeito do update_last_seen_on_conversation do
# Api::V1::Accounts::ConversationsController (que passa a chamar este serviço, ConversaCanal::LidoNoServidorDoEmail):
# grava agent_last_seen_at (e assignee_last_seen_at quando pedido) sem callbacks e avisa os contadores de não lidas.
# A importação do e-mail usa o mesmo serviço quando a leitura vem do servidor do cliente.
class ConversaCanal::LidoDaConversa
  def initialize(conversation)
    @conversation = conversation
  end

  def marcar!(last_seen_at, atualizar_responsavel:)
    updates = { agent_last_seen_at: last_seen_at }
    updates[:assignee_last_seen_at] = last_seen_at if atualizar_responsavel.present?

    # rubocop:disable Rails/SkipsModelValidations
    @conversation.update_columns(updates)
    # rubocop:enable Rails/SkipsModelValidations

    ::Conversations::UnreadCounts::Notifier.new(@conversation).perform
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(@conversation.account).conversation_changed!
  end
end
