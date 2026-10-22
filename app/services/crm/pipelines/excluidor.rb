# Excluir de vez um funil arquivado (#2096, Parte C). Quem chama já conferiu administrador, funil arquivado e
# confirmação. Com cards, a escolha é explícita:
# - 'move': cada card vai para o funil de destino (Crm::Cards::Mover, com o histórico "move" e sem rodar as automações
#   da etapa de destino). O aberto vai para a etapa escolhida; o fechado e o arquivado, para a primeira etapa do destino,
#   porque não estão no quadro.
# - 'delete': os cards são apagados de vez junto (Crm::Cards::Excluidor, com o cancelamento das reuniões futuras).
# Tudo numa transação: se algo falhar, o funil e os cards ficam como estavam.
class Crm::Pipelines::Excluidor
  MOVER = 'move'.freeze
  APAGAR = 'delete'.freeze
  MODOS = [MOVER, APAGAR].freeze

  # A etapa que recebe os cards em 'move': de outro funil ativo da mesma conta. nil quando não serve.
  def self.etapa_de_destino(pipeline, stage_id)
    stage = pipeline.account.crm_pipeline_stages.includes(:pipeline).find_by(id: stage_id)
    stage if stage&.pipeline&.active? && stage.pipeline_id != pipeline.id
  end

  def initialize(pipeline:, actor:, modo: nil, target_stage: nil)
    @pipeline = pipeline
    @account = pipeline.account
    @actor = actor
    @modo = modo
    @target_stage = target_stage
  end

  def perform
    card_ids = @pipeline.cards.order(:id).pluck(:id)
    raise ArgumentError, 'pipeline has cards: choose move or delete' if card_ids.any? && MODOS.exclude?(@modo)
    return apagar_com_os_cards(card_ids) if @modo == APAGAR && card_ids.any?

    movidos = []
    ActiveRecord::Base.transaction do
      movidos = mover_cards!
      apagar_funil!(card_ids: [], cards_movidos: movidos.size)
    end
    movidos.each { |card| Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_MOVED) }
  end

  private

  def apagar_com_os_cards(card_ids)
    Crm::Cards::Excluidor.new(account: @account, card_ids: card_ids).perform do |ids|
      apagar_funil!(card_ids: ids, cards_movidos: 0)
    end
  end

  def mover_cards!
    return [] if @target_stage.blank?

    primeira_etapa = @target_stage.pipeline.stages.order(:position, :id).first
    @pipeline.cards.order(:id).map do |card|
      etapa = card.open? ? @target_stage : primeira_etapa
      Crm::Cards::Mover.new(card: card, actor: @actor, target_stage: etapa, automation_context: { skip_automations: true }).perform
    end
  end

  # O que aponta para o funil ou para as etapas dele sem cascata no banco sai antes do destroy; o resto o banco faz
  # (acesso por funil, agentes de IA por funil, metas por pessoa: cascade; passagens, decisões de assunto, prospecção:
  # nullify). As etapas saem com o funil (Crm::Pipeline has_many :stages, dependent: :destroy), e com elas as
  # automações, os passos e as sugestões da IA que apontavam para a etapa.
  def apagar_funil!(card_ids:, cards_movidos:)
    soltar_referencias!
    pipeline_id = @pipeline.id
    @pipeline.destroy!
    Crm::ExclusaoDefinitiva.auditar!(account: @account, user: @actor, alvo: 'funil', card_ids: card_ids,
                                     pipeline_id: pipeline_id, cards_movidos: cards_movidos)
    # Acesso por funil (#1148): quem cuidava deste funil deixa de ver por ele. Depois do commit.
    account_id = @account.id
    ActiveRecord.after_all_transactions_commit { Crm::Access::CountInvalidation.card_changed!(account_id) }
  end

  def soltar_referencias!
    da_conta = { account_id: @account.id }
    stage_ids = @pipeline.stages.pluck(:id)
    soltar_registros!(da_conta)
    soltar_configuracoes!(da_conta, stage_ids)
  end

  # rubocop:disable Rails/SkipsModelValidations
  def soltar_registros!(da_conta)
    # Execução de automação não tem cascata para a automação; a do card movido continuaria apontando para ela.
    Crm::StageAutomationExecution.where(stage_automation_id: Crm::StageAutomation.where(pipeline_id: @pipeline.id).select(:id))
                                 .delete_all
    # A ligação com a caixa aponta para a etapa padrão sem cascata: sai antes das etapas.
    @pipeline.pipeline_inboxes.destroy_all
    Crm::SavedView.where(da_conta).where(pipeline_id: @pipeline.id).delete_all
    # O custo de IA continua na conta; só o vínculo com o funil sai. Idem o registro de conversões da Meta.
    Crm::AiUsageEvent.where(da_conta).where(pipeline_id: @pipeline.id).update_all(pipeline_id: nil)
    Crm::MetaConversionEvent.where(da_conta).where(pipeline_id: @pipeline.id).update_all(pipeline_id: nil)
  end

  def soltar_configuracoes!(da_conta, stage_ids)
    Crm::InboxSetting.where(da_conta).where(default_pipeline_id: @pipeline.id).update_all(default_pipeline_id: nil, default_stage_id: nil)
    Crm::InboxSetting.where(da_conta).where(default_stage_id: stage_ids).update_all(default_stage_id: nil)
    # Página de agendamento sem funil cai no primeiro funil ativo (Crm::BookingV2::Booker.pipeline_target).
    Crm::AgentBookingProfile.where(da_conta).where(default_pipeline_id: @pipeline.id).update_all(default_pipeline_id: nil, default_stage_id: nil)
    Crm::AgentBookingProfile.where(da_conta).where(default_stage_id: stage_ids).update_all(default_stage_id: nil)
  end
  # rubocop:enable Rails/SkipsModelValidations
end
