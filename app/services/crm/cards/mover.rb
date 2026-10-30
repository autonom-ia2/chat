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
      @from_stage_name = @card.stage&.name
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
  # #1498: atendimento fechado que vai para um funil de Vender entra Aberto (Crm::Cards::Outcome.status_after_move).
  def move_card!
    @card.update!(
      pipeline: @target_stage.pipeline,
      stage: @target_stage,
      status: target_status,
      entered_stage_at: Time.current,
      last_activity_at: Time.current
    )
  end

  # Troca de etapa no mesmo funil segue como antes; só a mudança de funil reabre o atendimento fechado.
  def target_status
    pipeline = @target_stage.pipeline
    return Crm::Cards::Outcome.status_for(pipeline, @card.status) if @card.pipeline_id == pipeline.id

    Crm::Cards::Outcome.status_after_move(pipeline, @card.status)
  end

  # O nome das etapas vai junto: se uma delas for apagada, o histórico continua dizendo de onde para onde o card foi.
  def log_move!(from_stage_id:, from_pipeline_id:)
    Crm::ActivityLogger.new(
      card: @card,
      actor: @actor,
      event_type: 'move',
      payload: {
        from_pipeline_id: from_pipeline_id,
        to_pipeline_id: @card.pipeline_id,
        from_stage_id: from_stage_id,
        to_stage_id: @card.stage_id,
        from_stage_name: @from_stage_name,
        to_stage_name: @target_stage.name
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
