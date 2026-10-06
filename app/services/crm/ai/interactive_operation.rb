# Somente as operações interativas migradas: autorização na execução e na leitura do resultado.
class Crm::Ai::InteractiveOperation
  attr_reader :context

  def initialize(data)
    @data = data
    @inputs = data.fetch('inputs').deep_symbolize_keys
    @account = Account.find(data.fetch('account_id'))
    @account_user = @account.account_users.find(data.fetch('account_user_id'))
    @user = @account_user.user
    @context = { account: @account, account_user: @account_user, user: @user }
  end

  def authorize!
    authorize_requester!
    case @data.fetch('operation')
    when 'meeting_times', 'meeting_invite', 'meeting_summary' then authorize_meeting!
    when 'card_summary', 'card_evaluate' then authorize_card!
    when 'copilot_run', 'copilot_chat' then authorize_copilot!
    when 'agent_test', 'agent_suggest' then authorize_agent!
    when 'email_rewrite' then authorize_email!
    when 'stage_criteria' then authorize_pipeline!
    else raise ArgumentError, 'unknown_interactive_operation'
    end
  end

  def perform # rubocop:disable Metrics/CyclomaticComplexity
    case @data.fetch('operation')
    when 'meeting_times', 'meeting_invite', 'meeting_summary' then meeting_result
    when 'card_summary' then card_summary
    when 'card_evaluate'
      result = Crm::Ai::Evaluator.new(card: card, trigger: 'manual').perform
      { payload: { status: result.status, suggestion: suggestion_payload(result.suggestion) } }
    when 'copilot_run', 'copilot_chat' then copilot_result
    when 'agent_test', 'agent_suggest' then playground_result
    when 'email_rewrite' then EmailCampaigns::Ai::Rewriter.new(account: @account, **@inputs).perform
    when 'stage_criteria' then Crm::Ai::StageCriteriaImprover.new(pipeline: pipeline, **@inputs.except(:pipeline_id)).perform
    end
  end

  private

  def authorize_requester!
    raise Pundit::NotAuthorizedError unless @account.active?
    return unless @data['integration_token_id']

    token = Crm::IntegrationToken.find(@data['integration_token_id'])
    raise Pundit::NotAuthorizedError if token.revoked? || token.account_user_id != @account_user.id || @account_user.custom_role.blank?
  end

  def authorize_meeting!
    raise Pundit::NotAuthorizedError unless Crm::Config.enabled? && Crm::Config.calendar_meetings_enabled?(@account)

    Pundit.authorize(@context, card, :update?)
  end

  def authorize_card!
    raise Pundit::NotAuthorizedError unless Crm::Config.enabled? && Crm::Ai::Config.enabled?

    Pundit.authorize(@context, card, @data['operation'] == 'card_summary' ? :summarize? : :evaluate_ai?)
    authorize_conversation!(card.primary_conversation) if @data['operation'] == 'card_summary' && card.primary_conversation
  end

  def authorize_copilot!
    enabled = Crm::Config.enabled? && Autonomia::Agents::Config.enabled?(@account) &&
              ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_COPILOT_ENABLED', false))
    raise Pundit::NotAuthorizedError unless enabled

    authorize_conversation!(conversation)
  end

  def pipeline
    @pipeline ||= @account.crm_pipelines.find(@inputs.fetch(:pipeline_id))
  end

  def authorize_pipeline!
    raise Pundit::NotAuthorizedError unless Crm::Config.enabled? && Crm::Ai::Config.enabled?

    Pundit.authorize(@context, pipeline, :manage_ai?)
  end

  def authorize_email!
    raise Pundit::NotAuthorizedError unless EmailCampaigns::Config.enabled? && Crm::Ai::Config.enabled?

    Pundit.authorize(@context, EmailCampaign, :create?)
  end

  def authorize_agent!
    raise Pundit::NotAuthorizedError unless Autonomia::Agents::Config.enabled?(@account) && @account_user.permission_granted?('autonomia_view')

    agent
  end

  def copilot_result
    service = @data['operation'] == 'copilot_run' ? Autonomia::Copilot::ConversationCopilot : Autonomia::Copilot::ConversationChat
    service.new(conversation: conversation, **@inputs.except(:conversation_id)).perform.to_h
  end

  def meeting_result
    case @data.fetch('operation')
    when 'meeting_times'
      suggestions = Crm::Ai::SuggestMeetingTimeService.new(
        card: card, inbox: @account.inboxes.find(@inputs.fetch(:inbox_id)), agent: @user,
        **@inputs.slice(:date, :duration_minutes, :timezone)
      ).perform
      { suggestions: suggestions, ai_available: Crm::Ai::Config.enabled? && Crm::Ai::CredentialResolver.new(account: @account).configured? }
    when 'meeting_invite'
      Crm::Ai::DraftInviteService.new(card: card, title: @inputs[:title]).perform
    when 'meeting_summary'
      Crm::Ai::MeetingSummaryService.new(meeting: meeting).perform
    end
  end

  def card_summary
    result = Crm::Ai::ConversationSummarizer.new(card: card, force: true).perform
    { payload: { status: result.status, error: result.error,
                 ai_summary: result.text.present? ? { text: result.text, generated_at: result.generated_at } : nil } }
  end

  def meeting
    @meeting ||= @account.crm_meetings.find(@inputs.fetch(:meeting_id))
  end

  def card
    @card ||= @data['operation'] == 'meeting_summary' ? meeting.card : @account.crm_cards.find(@inputs.fetch(:card_id))
  end

  def conversation
    @conversation ||= @account.conversations.find(@inputs.fetch(:conversation_id))
  end

  def authorize_conversation!(record)
    Pundit.authorize(@context, record, :show?)
    Crm::Conversations::AccessAuthorizer.new(**@context).authorize!(record)
  end

  def agent
    @agent ||= Autonomia::Agents::Agent.kept.where(account: @account).where("config->>'system_key' IS NULL").find(@inputs.fetch(:agent_id))
  end

  def playground_result
    test = @data['operation'] == 'agent_test'
    args = @inputs.except(:agent_id)
    result = if test
               Autonomia::Agents::Playground.new(agent: agent, **args).run
             else
               Autonomia::Agents::Copilot.new(agent: agent, **args).suggest
             end
    JSON.parse(ApplicationController.render(
                 template: "api/v1/accounts/autonomia/agents/playground/#{test ? 'test' : 'suggest'}",
                 assigns: { agent: agent, result: result }, formats: [:json]
               ))
  end

  def suggestion_payload(suggestion)
    return if suggestion.blank?

    { id: suggestion.id, from_stage_id: suggestion.from_stage_id, to_stage_id: suggestion.to_stage_id,
      to_stage_name: suggestion.to_stage&.name, confidence: suggestion.confidence.to_f,
      reasoning: suggestion.reasoning, status: suggestion.status, created_at: suggestion.created_at }
  end
end
