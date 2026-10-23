# Mensagem editada pelo cliente no Instagram (#2113). Payload da Meta (instagram-platform/webhooks/examples):
#   messaging[].message_edit = { mid, text, num_edit }
# vale para os dois logins (Instagram e página do Facebook). O texto novo substitui o `content` da mensagem do cliente
# com o mesmo `mid` na caixa; o anterior fica no `edit_history` (Waha::RichNative::Edits, o mesmo do WhatsApp), e a
# tela mostra "Editada". A ordem vem do `num_edit` (e da hora do evento): edição velha ou repetida não volta o texto.
# Fica de fora, sem erro: mid desconhecido (com log), mensagem que não é do cliente que editou, mensagem apagada (o
# Edits.apply! confere de novo sob a trava) e texto vazio ou acima do teto. A tradução do texto antigo sai junto.
class Instagram::MessageEditService
  def initialize(messaging:, channel:)
    @messaging = messaging
    @channel = channel
  end

  def perform
    return unless Waha::RichNative::Edits.valid_text?(edit[:text])

    message = target_message
    return if message.nil?

    Waha::RichNative::Edits.apply!(
      message,
      content: edit[:text],
      author: Waha::RichNative::Edits.contact_author(message.conversation.contact_id),
      timestamp: @messaging[:timestamp],
      sequence: sequence
    )
  end

  private

  def edit
    @edit ||= (@messaging[:message_edit] || {}).with_indifferent_access
  end

  def sequence
    number = edit[:num_edit]
    number if number.is_a?(Integer)
  end

  def target_message
    return if edit[:mid].blank?

    inbox = ::Inbox.find_by(channel: @channel)
    return if inbox.nil?

    message = inbox.messages.incoming.find_by(source_id: edit[:mid])
    # Sem a original (ainda não gravada ou de fora do painel), a edição fica de fora; o log dá o diagnóstico.
    if message.nil?
      Rails.logger.info("[instagram] message_edit sem mensagem original inbox=#{inbox.id} mid=#{edit[:mid]}")
      return
    end
    return if message.deleted.present?
    return unless message.conversation.contact_inbox&.source_id == @messaging.dig(:sender, :id).to_s

    message
  end
end
