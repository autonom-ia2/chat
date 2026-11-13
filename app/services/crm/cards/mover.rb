class Crm::Cards::Mover
  # #2428: quem moveu foi uma automação (`automacao: { origem: 'regra' | 'etapa' | 'livre', id: }`): a atividade grava
  # `by: 'automacao'`, a origem e o id, e a IA do funil respeita o movimento (Crm::Ai::MovimentoDaAutomacao).
  # etapa_de_entrada (#2501): o pedido da API não trouxe uma etapa do funil novo e o card entrou na etapa de entrada
  # dele (Crm::Cards::EtapaDeEntrada). A atividade grava o `motivo` (a pessoa não escolheu a etapa: sai do
  # Crm::Ai::EscolhaDePessoa, como o movimento em lote) e o nome do funil, para o histórico dizer por quê.
  # rubocop:disable Metrics/ParameterLists -- o motivo da etapa é dado do movimento, como a automação
  def initialize(card:, actor:, target_stage:, automation_context: {}, automacao: nil, etapa_de_entrada: nil)
    @card = card
    @actor = actor
    @target_stage = target_stage
    @automation_context = automation_context.to_h.with_indifferent_access
    @automacao = automacao
    @etapa_de_entrada = etapa_de_entrada
  end
  # rubocop:enable Metrics/ParameterLists

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
        to_stage_name: @target_stage.name,
        **da_automacao,
        **da_etapa_de_entrada,
        # #1920: a origem do movimento que não foi escolha direta de uma pessoa (Crm::Ai::EscolhaDePessoa).
        source: @automation_context[:source],
        automation_depth: @automation_context[:depth]
      }.compact
    ).perform
  end

  def da_automacao
    return {} if @automacao.blank?

    { by: 'automacao', origem: @automacao[:origem], automacao_id: @automacao[:id] }
  end

  def da_etapa_de_entrada
    return {} if @etapa_de_entrada.blank?

    { motivo: @etapa_de_entrada, to_pipeline_name: @target_stage.pipeline.name }
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
