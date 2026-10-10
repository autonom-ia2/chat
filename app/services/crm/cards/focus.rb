# Marca o card como o assunto atual da conversa (#1143): o vínculo com o focused_at mais recente.
# `user`: a pessoa que escolheu (botão de foco, aceite de sugestão). Nulo quando foi a IA ou o sistema. A IA de assunto
# não desfaz a escolha de uma pessoa por algumas horas (#1260).
class Crm::Cards::Focus
  def initialize(account:, card:, conversation:, user: nil)
    @account = account
    @card = card
    @conversation = conversation
    @user = user
  end

  def perform
    link = Crm::CardConversation.find_or_create_by!(account: @account, card: @card, conversation: @conversation)
    link.update!(focused_at: Time.current, focused_by_id: @user&.id)
    link
  end
end
