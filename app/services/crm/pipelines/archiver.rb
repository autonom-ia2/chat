# Arquivar um funil (#2095), com a opção de levar antes os cards abertos para uma etapa de outro funil ativo. Tudo vai
# numa transação: se algo falhar, nada muda.
#
# Sem destino, os cards abertos ficam no funil arquivado e voltam ao quadro quando ele for restaurado
# (Api::V1::Accounts::Crm::PipelinesController#restore). Os retornos marcados deles param
# (Crm::Pipelines::RetornosDosGuardados). Fechados e arquivados ficam sempre.
#
# Travas, nesta ordem:
# 1. a da conta, a mesma do PATCH de status (PipelinesController#save_pipeline!): dois arquivamentos ao mesmo tempo
#    se enfileiram, então não zeram os funis ativos nem se cruzam (arquivar P1 levando para P2 e P2 levando para P1);
# 2. o funil, relido: a regra do último funil ativo e do único principal (Crm::Pipeline#motivo_para_nao_arquivar)
#    vale para o estado de agora;
# 3. a etapa de destino e o funil dela, relidos: o destino arquivado, ou a etapa apagada, entre a escolha na tela e este
#    momento é recusado, sem prender os cards de novo;
# 4. os cards abertos que vão mudar.
#
# O card movido muda de funil pelo modelo (Crm::Card#update!), para valer o que a troca de funil dispara: a contagem do
# acesso por funil, o agente de IA responsável da caixa e a sugestão de repasse. A atividade 'move' de cada um sai em
# lote e leva `motivo: 'funil_arquivado'`, sem webhook nem conversão de anúncio e sem as automações das etapas: é a
# conta reorganizando funis, não o cliente avançando (o mesmo critério da etapa apagada, Crm::PipelineStages::Destroyer).
# O card cujo dono já saiu da conta vai sem dono (Crm::Card.donos_fora_da_conta): o modelo recusaria gravá-lo com ele.
class Crm::Pipelines::Archiver
  INVALID_TARGET = 'crm.pipeline_archive_invalid_target'.freeze
  MOTIVO = 'funil_arquivado'.freeze
  # O que o update! do card valida e lê: pré-carregado uma vez para o lote, não uma consulta por card.
  CARD_PRELOAD = %i[contact inbox team primary_conversation owner].freeze

  Result = Struct.new(:moved, :stopped_follow_ups, keyword_init: true)

  class InvalidTarget < StandardError; end

  # A regra do último funil ativo ou do único principal recusou (Crm::Pipeline#motivo_para_nao_arquivar).
  class Blocked < StandardError
    attr_reader :motivo

    def initialize(motivo)
      @motivo = motivo
      super("crm.pipeline_archive_#{motivo}")
    end
  end

  # target_stage: a etapa de destino, já resolvida entre as que a pessoa enxerga (o controller confere). Precisa ser de
  # outro funil ativo da mesma conta, e é conferida de novo sob a trava.
  def initialize(pipeline:, actor:, target_stage: nil)
    @pipeline = pipeline
    @actor = actor
    @target_stage = target_stage
  end

  def perform
    result = nil
    @pipeline.account.with_lock do
      @pipeline.lock!
      motivo = @pipeline.motivo_para_nao_arquivar
      raise Blocked, motivo if motivo

      target = lock_target!
      moved = target ? move_open_cards!(target) : []
      stopped = target ? 0 : Crm::Pipelines::RetornosDosGuardados.new(@pipeline).parar!
      @pipeline.archived! unless @pipeline.archived?
      result = Result.new(moved: moved, stopped_follow_ups: stopped)
    end
    result.moved.each { |card| Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_MOVED) }
    result
  end

  private

  def lock_target!
    return if @target_stage.nil?

    stage = Crm::PipelineStage.lock.find_by(id: @target_stage.id, account_id: @pipeline.account_id)
    target_pipeline = stage && Crm::Pipeline.lock.find_by(id: stage.pipeline_id)
    raise InvalidTarget, INVALID_TARGET unless target_pipeline&.active? && target_pipeline.id != @pipeline.id

    stage
  end

  def move_open_cards!(target)
    now = Time.current
    cards = @pipeline.cards.open.order(:id).lock.includes(*CARD_PRELOAD).to_a
    sem_dono = Crm::Card.donos_fora_da_conta(@pipeline.account_id, cards.map(&:owner_id))
    cards.each do |card|
      attributes = { pipeline: target.pipeline, stage: target, entered_stage_at: now, last_activity_at: now }
      attributes[:owner_id] = nil if sem_dono.include?(card.owner_id)
      card.update!(attributes)
    end
    # rubocop:disable Rails/SkipsModelValidations
    Crm::Activity.insert_all!(cards.map { |card| move_activity(card, target, now) }) if cards.any?
    # rubocop:enable Rails/SkipsModelValidations
    cards
  end

  def move_activity(card, target, now)
    {
      account_id: @pipeline.account_id, card_id: card.id, actor_type: @actor ? @actor.class.name.underscore : 'system',
      actor_id: @actor&.id, event_type: 'move', created_at: now,
      payload: { from_pipeline_id: @pipeline.id, to_pipeline_id: target.pipeline_id,
                 from_stage_id: card.stage_id_before_last_save, to_stage_id: target.id,
                 from_stage_name: stage_names[card.stage_id_before_last_save], to_stage_name: target.name,
                 motivo: MOTIVO }.merge(dono_que_saiu(card))
    }
  end

  # O dono que saiu da conta e foi tirado do card na mudança, para o histórico dizer por quê.
  def dono_que_saiu(card)
    return {} unless card.saved_change_to_owner_id?

    { dono_que_saiu_id: card.owner_id_before_last_save }
  end

  def stage_names
    @stage_names ||= @pipeline.stages.pluck(:id, :name).to_h
  end
end
