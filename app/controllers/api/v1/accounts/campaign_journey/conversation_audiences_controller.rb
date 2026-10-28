# "Novo público pedindo em palavras" (#2277): the person writes who they want, the account's own AI reads the
# conversations and builds the list to review and save as an audience.
#
#   GET  …/campaign_journey/conversation_audiences/status             own AI key?, conversations per period, the
#                                                                     person's search still open (to come back to it)
#   POST …/campaign_journey/conversation_audiences                    { request, period } → planning (PlanJob)
#   GET  …/campaign_journey/conversation_audiences/:id                plan, progress, cost and the people found
#   POST …/campaign_journey/conversation_audiences/:id/answer         { answer } → planning again, with the answer
#   POST …/campaign_journey/conversation_audiences/:id/start          planned → queued (ReadJob)
#   POST …/campaign_journey/conversation_audiences/:id/stop           stops the readers; who was found stays
#   POST …/campaign_journey/conversation_audiences/:id/resume         stopped, ceiling or failed → queued again
#   GET  …/campaign_journey/conversation_audiences/:id/conversation   ?person_id= the messages that prove it
#   POST …/campaign_journey/conversation_audiences/:id/save           { name, person_ids } → a saved audience
#
# Who: an administrator, or a role with campaign_manage AND conversation_view (the search reads every conversation of
# the account). Each search belongs to the person who asked. Off (flag of the account, campaigns or audiences off) → 404.
class Api::V1::Accounts::CampaignJourney::ConversationAudiencesController < Api::V1::Accounts::BaseController
  FLAG = 'campanhas_publico_por_conversa'.freeze

  before_action :ensure_enabled
  before_action -> { check_permission_granted!('campaign_manage') }
  before_action -> { check_permission_granted!('conversation_view') }
  before_action :fetch_search, except: [:status, :create]

  def status
    open = searches.where.not(status: ConversationAudienceSearch::SAVED).order(created_at: :desc).first
    render json: {
      has_own_key: ConversationAudience::Credential.for(Current.account).present?,
      periods: ConversationAudience::Conversations.counts(Current.account, Current.user),
      open_search_id: open&.id
    }
  end

  # A search whose job was lost (deploy, process killed) gets a new one when the screen looks at it — once: only the
  # call that moves the old heartbeat enqueues (the screen asks every few seconds).
  def show
    token = ConversationAudienceSearch.revive(@search.id)
    ConversationAudience::ReadJob.perform_later(@search.id, token) if token
    ConversationAudience::PlanJob.perform_later(@search.id) if ConversationAudienceSearch.replan(@search.id)
    render json: ConversationAudience::Payload.new(@search.reload, since: since).to_h
  end

  # One search at a time per person: each new request pays the planner on the account's key.
  def create
    return render_unprocessable('search_in_progress') if searches.exists?(status: ConversationAudienceSearch::BUSY)

    search = searches.create!(request: params[:request].to_s.strip, period: params[:period].to_s)
    ConversationAudience::PlanJob.perform_later(search.id)
    render json: payload(search), status: :created
  end

  def answer
    return render_unprocessable('search_in_progress') if busy_elsewhere?

    answer = params[:answer].to_s.strip.first(ConversationAudienceSearch::REQUEST_MAX)
    moved = ConversationAudienceSearch.move(@search.id, from: ConversationAudienceSearch::QUESTION, to: ConversationAudienceSearch::PLANNING,
                                                        answer: answer)
    return render_unprocessable('not_waiting_answer') unless moved

    ConversationAudience::PlanJob.perform_later(@search.id)
    render json: payload(@search.reload)
  end

  def start
    queue(from: [ConversationAudienceSearch::PLANNED])
  end

  def resume
    return render_unprocessable('cannot_resume') unless @search.resumable? && @search.batches.pending.exists?

    # Going on past the ceiling is the person's choice on the screen: the new ceiling covers the rest of the reading.
    rest = @search.batches.pending
    ceiling = @search.spent_usd + (ConversationAudience::Cost.estimate_usd(rest.sum(:chars), rest.count) *
                                   ConversationAudience::Cost::CEILING_FACTOR)
    @search.update!(ceiling_usd: [@search.ceiling_usd.to_d, ceiling].max)
    # "Tentar de novo" after the AI was out gives each batch its tries again.
    rest.update_all(attempts: 0) # rubocop:disable Rails/SkipsModelValidations
    queue(from: ConversationAudienceSearch::RESUMABLE, error: nil)
  end

  def stop
    return render_unprocessable('not_running') unless @search.running?

    # Still in line, nothing was read nor paid: the plan comes back, ready for "Começar" again.
    back = @search.conversations_read.zero? &&
           ConversationAudienceSearch.move(@search.id, from: ConversationAudienceSearch::QUEUED, to: ConversationAudienceSearch::PLANNED)
    unless back
      ConversationAudienceSearch.move(@search.id, from: ConversationAudienceSearch::RUNNING, to: ConversationAudienceSearch::STOPPED,
                                                  finished_at: Time.current)
    end
    # The slot is given back by the job, after the wave in flight ends: two waves of one account never overlap.
    render json: payload(@search.reload)
  end

  def conversation
    person = @search.people.find(params[:person_id])
    render json: { payload: ConversationAudience::Peek.new(person, user: Current.user).messages }
  end

  def save
    return render_unprocessable('not_finished') if @search.running? || @search.status == ConversationAudienceSearch::SAVED

    audience = ConversationAudience::Save.new(@search, user: Current.user, name: params[:name].to_s,
                                                       person_ids: params.permit(person_ids: [])[:person_ids]).perform
    render json: { id: audience.id, name: audience.name, count: audience.valid_rows }
  rescue ConversationAudience::Save::Error => e
    render_unprocessable(e.message)
  end

  private

  def ensure_enabled
    enabled = ::CampaignJourney::Config.enabled? && ::CampaignImports::Config.enabled? && Current.account.feature_enabled?(FLAG)
    head :not_found unless enabled
  end

  def searches
    ConversationAudienceSearch.where(account_id: Current.account.id, user_id: Current.user.id)
  end

  def fetch_search
    @search = searches.find(params[:id])
  end

  # One search working on the account's key per person: a second one waits for the first (#2303 review).
  def busy_elsewhere?
    searches.where.not(id: @search.id).exists?(status: ConversationAudienceSearch::BUSY)
  end

  def queue(from:, **attributes)
    return render_unprocessable('search_in_progress') if busy_elsewhere?

    token = ConversationAudienceSearch.queue!(@search.id, from: from, **attributes)
    return render_unprocessable('wrong_status') unless token

    ConversationAudience::ReadJob.perform_later(@search.id, token)
    render json: payload(@search.reload)
  end

  def payload(search)
    ConversationAudience::Payload.new(search).to_h
  end

  # The cursor of the previous answer; anything else reads the whole list.
  def since
    Time.iso8601(params[:since].to_s)
  rescue ArgumentError
    nil
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
