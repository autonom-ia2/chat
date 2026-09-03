# Revisão das sugestões de FAQ de um agente (#284 · 2b): lista paginada por status, aprovar
# (com edição opcional = `edited`) e ignorar. Admin da conta (BaseController + policy própria).
class Api::V1::Accounts::Autonomia::Agents::FaqSuggestionsController < Api::V1::Accounts::Autonomia::BaseController
  RESULTS_PER_PAGE = 25

  before_action :fetch_agent
  before_action :fetch_suggestion, only: %i[approve ignore]

  def index
    authorize(::Autonomia::Agents::FaqSuggestion, :index?, policy_class: ::Autonomia::Agents::FaqSuggestionPolicy)
    scope = suggestions_scope.where(status: status_filter).ordered
    @current_page = [params[:page].to_i, 1].max
    @total_count = scope.count
    @suggestions = scope.page(@current_page).per(RESULTS_PER_PAGE)
    @pending_count = suggestions_scope.pending.count
  end

  def approve
    authorize(@suggestion, :approve?, policy_class: ::Autonomia::Agents::FaqSuggestionPolicy)
    edits = params.fetch(:faq_suggestion, {}).permit(:question, :answer)
    ::Autonomia::Agents::Faq::Approver.new(suggestion: @suggestion, user: Current.user)
                                      .approve!(question: edits[:question], answer: edits[:answer])
    render :show
  rescue ::Autonomia::Agents::Faq::Approver::NotPending
    render_unprocessable(I18n.t('autonomia.faq.not_pending'))
  rescue ::Autonomia::Agents::EmbeddingService::EmbeddingError
    render_unprocessable(I18n.t('autonomia.faq.embedding_failed'))
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable(e.record.errors.full_messages.to_sentence)
  end

  def ignore
    authorize(@suggestion, :ignore?, policy_class: ::Autonomia::Agents::FaqSuggestionPolicy)
    ::Autonomia::Agents::Faq::Approver.new(suggestion: @suggestion, user: Current.user).ignore!
    render :show
  rescue ::Autonomia::Agents::Faq::Approver::NotPending
    render_unprocessable(I18n.t('autonomia.faq.not_pending'))
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def fetch_suggestion
    @suggestion = suggestions_scope.find(params[:id])
  end

  def suggestions_scope
    @agent.faq_suggestions.where(account_id: Current.account.id)
  end

  def status_filter
    status = params[:status].to_s
    ::Autonomia::Agents::FaqSuggestion.statuses.key?(status) ? status : 'pending'
  end
end
