class Crm::StageAutomations::Runner
  def initialize(card:, actor:, from_stage_id:, to_stage_id:, exited_at: Time.current, automation_context: {})
    @card = card
    @actor = actor
    @from_stage_id = from_stage_id
    @to_stage_id = to_stage_id
    @exited_at = exited_at
    @automation_context = automation_context.to_h.with_indifferent_access
  end

  def perform
    return unless ::Crm::Config.enabled?
    return if @automation_context[:depth].to_i >= Crm::StageAutomations::StepExecutor::MAX_AUTOMATION_DEPTH

    run_for_stage(@from_stage_id, :on_exit) if @from_stage_id.present? && @from_stage_id != @to_stage_id
    run_for_stage(@to_stage_id, :on_enter) if @to_stage_id.present?
  end

  private

  def run_for_stage(stage_id, trigger_event)
    automations = @card.account.crm_stage_automations
                       .enabled
                       .where(stage_id: stage_id, trigger_event: trigger_event)
                       .includes(:steps)
                       .ordered

    automations.find_each do |automation|
      run_automation(automation, stage_id, trigger_event)
    end
  end

  def run_automation(automation, stage_id, trigger_event)
    trigger_token = build_trigger_token(stage_id, trigger_event)
    execution = find_or_create_execution!(automation, trigger_token)
    # Esperando o Decisor (#858): os passos seguintes são do job dele, não de um novo disparo.
    return if execution.completed? || execution.failed? || execution.metadata.to_h['decisor'].present?

    Crm::StageAutomations::StepSequence.new(card: @card, actor: @actor, execution: execution, automation_context: @automation_context)
                                       .perform(automation.steps.ordered.to_a)
  end

  def find_or_create_execution!(automation, trigger_token)
    existing = @card.account.crm_stage_automation_executions.find_by(
      card_id: @card.id,
      stage_automation_id: automation.id,
      trigger_token: trigger_token
    )
    return existing if existing.present?

    @card.account.crm_stage_automation_executions.create!(
      card: @card,
      stage_automation: automation,
      trigger_token: trigger_token,
      status: :running
    )
  end

  def build_trigger_token(stage_id, trigger_event)
    if trigger_event.to_s == 'on_enter'
      Crm::StageAutomations::TriggerToken.for_enter(card: @card, stage_id: stage_id)
    else
      Crm::StageAutomations::TriggerToken.for_exit(
        card: @card,
        from_stage_id: stage_id,
        exited_at: @exited_at
      )
    end
  end
end
