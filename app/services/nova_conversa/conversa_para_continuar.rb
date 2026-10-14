# Em qual conversa entra a mensagem que o atendente escreve pela gaveta "Nova conversa" (chat#1505). Segue a mesma
# regra da caixa que vale quando o cliente escreve (Whatsapp::IncomingMessageBaseService#set_conversation):
# - "Reabrir a mesma conversa" (lock_to_single_conversation): a última conversa do contato na caixa, qualquer situação;
# - "Criar novas conversas": a última que não foi resolvida (aberta, pendente ou adiada);
# - senão, nenhuma: a gaveta cria conversa nova.
# Uma consulta por caixa; a lista de caixas do contato chama isto uma vez para cada uma.
class NovaConversa::ConversaParaContinuar
  pattr_initialize [:inbox!, :contact!]

  def conversation
    return if contact.blank?

    scope = Conversation.where(account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact.id)
    scope = scope.where.not(status: :resolved) unless locked?
    scope.order(:id).last
  end

  def payload
    found = conversation
    return if found.blank?

    {
      id: found.id,
      display_id: found.display_id,
      status: found.status,
      last_activity_at: found.last_activity_at.to_i,
      locked: locked?
    }
  end

  private

  def locked?
    inbox.lock_to_single_conversation?
  end
end
