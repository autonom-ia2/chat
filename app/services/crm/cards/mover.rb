class Crm::Cards::Mover
  def initialize(card:, actor:, target_stage:, automation_context: {})
    @card = card
    @actor = actor
    @target_stage = target_stage
    @automation_context = automation_context.to_h.with_indifferent_access
  end

  def perform
    return @card if same_stage?

    exited_at = Time.current
    from_stage_id = nil

    ActiveRecord::Base.transaction do
      from_stage_id = @card.stage_id
      from_pipeline_id = @card.pipeline_id

      move_card!
      log_move!(from_stage_id: from_stage_id, from_pipeline_id: from_pipeline_id)
    end

    run_stage_automations!(from_stage_id: from_stage_id, exited_at: exited_at)
    @card
  end

  private

  def same_stage?
    @card.stage_id == @target_stage.id
  end

  # Card fechado que muda para funil de outro tipo leva o desfecho equivalente (ganho <-> resolvido, #1144).
  def move_card!
    @card.update!(
      pipeline: @target_stage.pipeline,
      stage: @target_stage,
      status: Crm::Cards::Outcome.status_for(@target_stage.pipeline, @card.status),
      entered_stage_at: Time.current,
      last_activity_at: Time.current
    )
  end

  def log_move!(from_stage_id:, from_pipeline_id:)
    Crm::ActivityLogger.new(
      card: @card,
      actor: @actor,
      event_type: 'move',
      payload: {
        from_pipeline_id: from_pipeline_id,
        to_pipeline_id: @card.pipeline_id,
        from_stage_id: from_stage_id,
        to_stage_id: @card.stage_id
      }
    ).perform
  end

  def run_stage_automations!(from_stage_id:, exited_at:)
    return if @automation_context[:skip_automations]

    Crm::StageAutomations::Runner.new(
      card: @card,
      actor: @actor,
      from_stage_id: from_stage_id,
      to_stage_id: @card.stage_id,
      exited_at: exited_at,
      automation_context: @automation_context
    ).perform
  end
end
