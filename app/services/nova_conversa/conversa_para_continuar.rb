# Em qual conversa entra a mensagem que o atendente escreve pela gaveta "Nova conversa" (chat#1505). A conversa é
# procurada no mesmo contact_inbox que a gaveta usa para criar (o source_id que contactable_inboxes devolve para a
# caixa), como fazem o ConversationBuilder e o recebimento: a mostrada é exatamente aquela em que a mensagem entraria.
# Regra da caixa, igual à de Whatsapp::IncomingMessageBaseService#set_conversation:
# - "Reabrir a mesma conversa" (lock_to_single_conversation): a última, qualquer situação;
# - "Criar novas conversas": a última que não foi resolvida (aberta, pendente ou adiada);
# - senão, nenhuma: a gaveta cria conversa nova.
# Só mostra o que a pessoa pode ver (ConversationPolicy#show?, que inclui o acesso por funil). Conversa que ela não
# pode ver: com "Criar novas", nada a oferecer (cria outra, como hoje); com "Reabrir", o builder entraria nela de
# qualquer jeito, então a gaveta é avisada sem número nem situação (`visible: false`).
class NovaConversa::ConversaParaContinuar
  pattr_initialize [:inbox!, :contact!, :source_id!, :user_context!]

  def conversation
    return if contact_inbox.blank?

    scope = contact_inbox.conversations
    scope = scope.where.not(status: :resolved) unless locked?
    scope.last
  end

  def payload
    found = conversation
    return if found.blank?
    return visible_payload(found) if visible?(found)

    hidden_payload if locked?
  end

  private

  def contact_inbox
    return if source_id.blank?

    @contact_inbox ||= ContactInbox.find_by(inbox_id: inbox.id, contact_id: contact.id, source_id: source_id)
  end

  def locked?
    inbox.lock_to_single_conversation?
  end

  def visible?(found)
    Pundit.policy!(user_context, found).show?
  end

  def visible_payload(found)
    {
      id: found.id, display_id: found.display_id, status: found.status,
      last_activity_at: found.last_activity_at.to_i, locked: locked?, visible: true
    }
  end

  def hidden_payload
    { id: nil, display_id: nil, status: nil, last_activity_at: nil, locked: true, visible: false }
  end
end
