# Marca o card como o assunto atual da conversa (#1143): o vínculo com o focused_at mais recente.
# `user`: a pessoa que escolheu (botão de foco, aceite de sugestão). Nulo quando foi a IA ou o sistema. A IA de assunto
# não desfaz a escolha de uma pessoa por algumas horas (#1260).
# `avaliar: false` (#1693): o foco só volta ao card que já era o assunto; quem avalia os cards da mensagem é a avaliação
# conjunta (Crm::Conversations::CardsTocados).
class Crm::Cards::Focus
  def initialize(account:, card:, conversation:, user: nil, avaliar: true)
    @account = account
    @card = card
    @conversation = conversation
    @user = user
    @avaliar = avaliar
  end

  # Uma pessoa escolheu o assunto atual desta conversa há menos de Crm::Subjects::RESPEITO_AO_FOCO. O atual é o foco
  # mais recente entre os cards abertos, como no ConversationCardFinder.
  def self.pessoa_escolheu?(account_id:, conversation_id:)
    atual = Crm::CardConversation.joins(:card).merge(Crm::Card.open)
                                 .where(account_id: account_id, conversation_id: conversation_id)
                                 .where.not(focused_at: nil).order(focused_at: :desc).first
    atual.present? && atual.focused_by_id.present? && atual.focused_at >= Crm::Subjects::RESPEITO_AO_FOCO.ago
  end

  def perform
    link = Crm::CardConversation.find_or_create_by!(account: @account, card: @card, conversation: @conversation)
    link.update!(focused_at: Time.current, focused_by_id: @user&.id)
    # O assunto mudou: a IA avalia o card que passou a ser o atual (#1147); o anterior deixa de ser avaliado.
    Crm::Ai::Observer.new(card: @card).schedule_evaluation if @avaliar
    link
  end
end
