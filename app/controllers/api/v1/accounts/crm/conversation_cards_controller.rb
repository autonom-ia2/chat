# Assuntos de uma conversa (#1143): os cards dela na ordem do ConversationCardFinder (assunto atual primeiro) e a troca
# manual do assunto atual. A conversa chega pelo display_id, como no resto do painel. Multifunil 5b: a sugestão da IA
# que espera resposta (modo Sugerir) vem junto da lista, e a pessoa aceita ou ignora.
class Api::V1::Accounts::Crm::ConversationCardsController < Api::V1::Accounts::Crm::BaseController
  before_action :load_conversation

  def index
    cards = conversation_cards.includes(:stage, :pipeline, :owner).to_a
    current_id = cards.first&.id if cards.first&.open?
    render json: { payload: cards.map { |card| card_payload(card, current_id) }, suggestion: suggestion_payload }
  end

  def accept_suggestion
    decision = pending_suggestion
    authorize_suggestion!(decision)
    card = ::Crm::Subjects::SuggestionResponder.new(decision: decision, user: Current.user).accept
    render json: { payload: { card_id: card.id } }
  rescue ::Crm::Subjects::SuggestionResponder::Error => e
    render_unprocessable("crm.conversation_cards.#{e.code}")
  end

  def dismiss_suggestion
    decision = pending_suggestion
    authorize_suggestion!(decision)
    ::Crm::Subjects::SuggestionResponder.new(decision: decision, user: Current.user).dismiss
    head :no_content
  rescue ::Crm::Subjects::SuggestionResponder::Error => e
    render_unprocessable("crm.conversation_cards.#{e.code}")
  end

  def focus
    card = conversation_cards.find(params.require(:card_id))
    authorize card, :update?
    # Ganho, perdido ou arquivado não volta a ser o assunto da conversa: pedido novo vira card novo.
    return render_unprocessable('crm.conversation_cards.closed_card') unless card.open?

    ::Crm::Cards::Focus.new(account: Current.account, card: card, conversation: @conversation).perform
    render json: { payload: { card_id: card.id } }
  end

  private

  def load_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize_crm_conversation!(@conversation)
  end

  def pending_suggestion
    ::Crm::SubjectDecision.where(account_id: Current.account.id, conversation_id: @conversation.id)
                          .find(params.require(:suggestion_id))
  end

  # Dar nome ou voltar a um assunto é editar aquele card; criar (ou sugestão cujo card sumiu) é permissão de criar.
  def authorize_suggestion!(decision)
    decision.card ? authorize(decision.card, :update?) : authorize(::Crm::Card, :create?)
  end

  # A sugestão esperando, se ainda faz sentido (card aberto, funil ativo na caixa) e a pessoa enxerga o card dela.
  def suggestion_payload
    decision = ::Crm::SubjectDecision.suggested.where(account_id: Current.account.id, conversation_id: @conversation.id)
                                     .includes(:pipeline, :card).order(id: :desc).first
    return unless decision && suggestion_visible?(decision)

    { id: decision.id, action: decision.action, title: decision.title, pipeline_name: decision.pipeline&.name,
      card_id: decision.card_id, card_title: decision.card&.title }
  end

  def suggestion_visible?(decision)
    return false unless ::Crm::Subjects::SuggestionResponder.applicable?(decision)

    decision.card_id.nil? || policy_scope(::Crm::Card).exists?(id: decision.card_id)
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
      outcome_labels: card.pipeline&.metadata&.dig('outcome_labels'),
      stage_name: card.stage&.name,
      stage_color: card.stage&.color,
      owner: card.owner && { id: card.owner.id, name: card.owner.available_name, avatar_url: card.owner.avatar_url }
    }
  end
end
