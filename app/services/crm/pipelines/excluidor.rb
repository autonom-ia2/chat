# Excluir de vez um funil arquivado (#2096, Parte C). Quem chama já conferiu administrador e confirmação. Com cards, a
# escolha é explícita:
# - 'move': cada card vai para o funil de destino (Crm::Cards::Mover, com o histórico "move" e sem rodar as automações
#   da etapa de destino). Card que fica aberto no destino vai para a etapa escolhida; o que fica fechado ou arquivado
#   vai para a primeira etapa do destino, porque não aparece no quadro. Quem decide é o status DEPOIS de mudar de
#   funil (Crm::Cards::Outcome.status_after_move): o atendimento Resolvido ou Cancelado que vai para um funil de Vender
#   volta aberto, e entra na etapa escolhida, no quadro.
# - 'delete': os cards são apagados de vez junto (Crm::Cards::Excluidor, com o cancelamento das reuniões futuras).
#
# Tudo numa transação, que começa travando o funil e o relendo: funil restaurado, apagado por outro pedido igual (dois
# cliques, dois jobs) ou com cards diferentes dos conferidos faz o pedido desistir sem apagar nada
# (Crm::ExclusaoDefinitiva::Mudou). Os cards são calculados já sob a trava; a auditoria leva só o que saiu de fato.
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
    return apagar_com_os_cards(card_ids) if @modo == APAGAR && card_ids.any?

    movidos = ActiveRecord::Base.transaction do
      travar_funil!
      mover_cards!.tap { |cards| apagar_funil!(card_ids: [], cards_movidos: cards.size) }
    end
    movidos.each { |card| Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_MOVED) }
  end

  private

  def apagar_com_os_cards(card_ids)
    raise Crm::ExclusaoDefinitiva::Mudou, 'not_archived' unless Crm::Pipeline.archived.exists?(id: @pipeline.id)

    conferir = lambda do |ids|
      travar_funil!
      raise Crm::ExclusaoDefinitiva::Mudou, 'cards_changed' if @pipeline.cards.order(:id).pluck(:id) != ids
    end
    Crm::Cards::Excluidor.new(account: @account, card_ids: card_ids, somente_arquivados: false).perform(conferir: conferir) do |ids|
      apagar_funil!(card_ids: ids, cards_movidos: 0)
    end
  end

  # Relê o funil com a trava. Restaurar (PATCH status) e arquivar travam a mesma linha: esperam este pedido, ou este
  # espera o deles e vê o resultado.
  def travar_funil!
    travado = Crm::Pipeline.lock.find_by(id: @pipeline.id)
    raise Crm::ExclusaoDefinitiva::Mudou, 'already_deleted' if travado.blank?
    raise Crm::ExclusaoDefinitiva::Mudou, 'not_archived' unless travado.archived?

    @pipeline = travado
  end

  def mover_cards!
    cards = @pipeline.cards.order(:id).to_a
    return [] if cards.empty?
    raise Crm::ExclusaoDefinitiva::Mudou, 'pipeline_has_cards' if @modo != MOVER

    destino = travar_destino!
    primeira_etapa = destino.stages.order(:position, :id).first
    cards.map do |card|
      Crm::Cards::Mover.new(card: card, actor: @actor, target_stage: etapa_para(card, destino, primeira_etapa),
                            automation_context: { skip_automations: true }).perform
    end
  end

  # O funil de destino não pode ser arquivado enquanto recebe os cards (FOR SHARE barra o UPDATE dele até o fim).
  def travar_destino!
    destino = Crm::Pipeline.lock('FOR SHARE').find_by(id: @target_stage&.pipeline_id, account_id: @account.id)
    raise Crm::ExclusaoDefinitiva::Mudou, 'target_unavailable' unless destino&.active? && destino.stages.exists?(id: @target_stage.id)

    destino
  end

  def etapa_para(card, destino, primeira_etapa)
    Crm::Cards::Outcome.status_after_move(destino, card.status).to_s == 'open' ? @target_stage : primeira_etapa
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
