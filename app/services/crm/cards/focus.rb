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
    # O assunto mudou: a IA avalia o card que passou a ser o atual (#1147); o anterior deixa de ser avaliado.
    Crm::Ai::Observer.new(card: @card).schedule_evaluation
    link
  end
end
