# Assuntos de uma conversa (#1143): os cards dela na ordem do ConversationCardFinder (assunto atual primeiro) e a troca
# manual do assunto atual. A conversa chega pelo display_id, como no resto do painel.
class Api::V1::Accounts::Crm::ConversationCardsController < Api::V1::Accounts::Crm::BaseController
  before_action :load_conversation

  def index
    cards = conversation_cards.includes(:stage, :pipeline, :owner).to_a
    current_id = cards.first&.id if cards.first&.open?
    render json: { payload: cards.map { |card| card_payload(card, current_id) } }
  end

  def focus
    card = conversation_cards.find(params.require(:card_id))
    authorize card, :update?
    # Ganho, perdido ou arquivado não volta a ser o assunto da conversa: pedido novo vira card novo.
    return render_unprocessable('crm.conversation_cards.closed_card') unless card.open?

    link = ::Crm::CardConversation.find_or_create_by!(account: Current.account, card: card, conversation: @conversation)
    link.update!(focused_at: Time.current)
    render json: { payload: { card_id: card.id } }
  end

  private

  def load_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize_crm_conversation!(@conversation)
  end

  def conversation_cards
    ::Crm::Cards::ConversationCardFinder.new(account: Current.account).all(@conversation)
                                        .where(id: policy_scope(::Crm::Card).select(:id))
  end

  def card_payload(card, current_id)
    {
      id: card.id,
      title: card.title,
      status: card.status,
      current: card.id == current_id,
      pipeline_id: card.pipeline_id,
      pipeline_name: card.pipeline&.name,
      stage_name: card.stage&.name,
      stage_color: card.stage&.color,
      owner: card.owner && { id: card.owner.id, name: card.owner.available_name, avatar_url: card.owner.avatar_url }
    }
  end
end
