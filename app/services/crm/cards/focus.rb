# Marca o card como o assunto atual da conversa (#1143): o vínculo com o focused_at mais recente.
class Crm::Cards::Focus
  def initialize(account:, card:, conversation:)
    @account = account
    @card = card
    @conversation = conversation
  end

  def perform
    link = Crm::CardConversation.find_or_create_by!(account: @account, card: @card, conversation: @conversation)
    link.update!(focused_at: Time.current)
    link
  end
end
