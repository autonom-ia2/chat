# Arquivar um funil (#2095), com a opção de levar antes os cards abertos para uma etapa de outro funil ativo. Mover e
# arquivar vão juntos numa transação: se algo falhar, nada muda.
#
# Sem destino, os cards abertos ficam no funil arquivado e voltam ao quadro quando ele for restaurado
# (Api::V1::Accounts::Crm::PipelinesController#restore). Fechados e arquivados ficam sempre.
#
# O card movido muda de funil pelo modelo (Crm::Card#update!), para valer o que a troca de funil dispara: a contagem do
# acesso por funil, o agente de IA responsável da caixa e a sugestão de repasse. A atividade 'move' de cada um sai em
# lote e leva `motivo: 'funil_arquivado'`, sem webhook nem conversão de anúncio e sem as automações das etapas: é a
# conta reorganizando funis, não o cliente avançando (o mesmo critério da etapa apagada, Crm::PipelineStages::Destroyer).
class Crm::Pipelines::Archiver
  INVALID_TARGET = 'crm.pipeline_archive_invalid_target'.freeze
  MOTIVO = 'funil_arquivado'.freeze

  class InvalidTarget < StandardError; end

  # target_stage: a etapa de destino, já resolvida entre as que a pessoa enxerga (o controller confere). Precisa ser de
  # outro funil ativo da mesma conta.
  def initialize(pipeline:, actor:, target_stage: nil)
    @pipeline = pipeline
    @actor = actor
    @target_stage = target_stage
  end

  # Devolve os cards movidos.
  def perform
    validate_target!
    moved = []
    ActiveRecord::Base.transaction do
      @pipeline.lock!
      moved = move_open_cards! if @target_stage
      @pipeline.archived!
    end
    moved.each { |card| Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_MOVED) }
    moved
  end

  private

  def validate_target!
    return if @target_stage.nil?
    return if @target_stage.account_id == @pipeline.account_id && @target_stage.pipeline_id != @pipeline.id &&
              @target_stage.pipeline.active?

    raise InvalidTarget, INVALID_TARGET
  end

  def move_open_cards!
    now = Time.current
    cards = @pipeline.cards.open.order(:id).lock.to_a
    cards.each do |card|
      card.update!(pipeline: @target_stage.pipeline, stage: @target_stage, entered_stage_at: now, last_activity_at: now)
    end
    # rubocop:disable Rails/SkipsModelValidations
    Crm::Activity.insert_all!(cards.map { |card| move_activity(card, now) }) if cards.any?
    # rubocop:enable Rails/SkipsModelValidations
    cards
  end

  def move_activity(card, now)
    {
      account_id: @pipeline.account_id, card_id: card.id, actor_type: @actor ? @actor.class.name.underscore : 'system',
      actor_id: @actor&.id, event_type: 'move', created_at: now,
      payload: { from_pipeline_id: @pipeline.id, to_pipeline_id: @target_stage.pipeline_id,
                 from_stage_id: card.stage_id_before_last_save, to_stage_id: @target_stage.id,
                 from_stage_name: stage_names[card.stage_id_before_last_save], to_stage_name: @target_stage.name,
                 motivo: MOTIVO }
    }
  end

  def stage_names
    @stage_names ||= @pipeline.stages.pluck(:id, :name).to_h
  end
end
