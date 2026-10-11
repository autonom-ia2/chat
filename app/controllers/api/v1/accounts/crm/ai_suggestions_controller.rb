class Api::V1::Accounts::Crm::AiSuggestionsController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_crm_ai_enabled
  before_action :fetch_suggestion

  def accept
    authorize @suggestion, :accept?
    return render_unprocessable('crm.ai.suggestion_not_pending') unless @suggestion.pending?

    ensure_move_allowed!(@suggestion.to_stage.pipeline_id)
    @card = Crm::Ai::SuggestionApplier.new(
      card: @suggestion.card,
      suggestion: @suggestion,
      actor: Current.user,
      auto: false
    ).perform
    render 'api/v1/accounts/crm/cards/show'
  end

  def dismiss
    authorize @suggestion, :dismiss?
    return render_unprocessable('crm.ai.suggestion_not_pending') unless @suggestion.pending?

    ensure_move_allowed!

    @suggestion.update!(status: :dismissed)
    Crm::ActivityLogger.new(
      card: @suggestion.card,
      actor: Current.user,
      event_type: 'ai_dismissed',
      payload: { suggestion_id: @suggestion.id }
    ).perform
    head :ok
  end

  private

  def fetch_suggestion
    @suggestion = Current.account.crm_ai_stage_suggestions.find(params[:id])
  end

  # Acesso por funil (#1148): aceitar move o card (o mesmo CardGuard do /move, com o funil do card e o de destino) e
  # recusar mexe nele (decisão b: exige o funil do card).
  def ensure_move_allowed!(target_pipeline_id = nil)
    guard = Crm::Access::CardGuard.new(user: Current.user, account: Current.account, account_user: Current.account_user)
    allowed = guard.edit_allowed?(@suggestion.card) && (target_pipeline_id.nil? || guard.move_allowed?(@suggestion.card, target_pipeline_id))
    raise Pundit::NotAuthorizedError unless allowed
  end
end
