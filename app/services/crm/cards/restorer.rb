# Restaurar um card arquivado (#2095): ele volta para a etapa onde estava e sai do arquivo pelo mesmo caminho do
# "reabrir" (Crm::Cards::Closer, result 'reopen'). Com a Parte A (#2091), o Closer devolve o desfecho que o card tinha
# ao ser arquivado (ganho, perdido...) com a data de antes; sem ela, o card volta aberto.
#
# A atividade é a do reabrir ('reopen', com `restored: true`): o webhook (CRM_CARD_REOPENED), a regra de 24 h da IA
# (Crm::Ai::FecharCard.fechados_pela_ia) e o histórico do card já conhecem esse evento. Um evento novo ficaria de fora
# dos três.
#
# Recusas, sem mudar nada:
# - NOT_ARCHIVED: o card não está arquivado;
# - PIPELINE_ARCHIVED: o funil dele está arquivado; restaure o funil antes, senão o card voltaria para um quadro que não
#   aparece;
# - CONFLICT: o card voltaria aberto e o contato já tem outro card aberto no mesmo funil (o cliente voltou). Com
#   `force: true`, restaura mesmo assim. O resultado traz esse card, para a tela oferecer "Abrir o card aberto". O
#   card que volta fechado (ganho, perdido) não vai ao quadro e não conflita: por isso a conferência é feita depois de
#   o Closer decidir o status, e desfeita junto com ele.
class Crm::Cards::Restorer
  NOT_ARCHIVED = 'crm.card_restore_not_archived'.freeze
  PIPELINE_ARCHIVED = 'crm.card_restore_pipeline_archived'.freeze
  CONFLICT = 'crm.card_restore_conflict'.freeze

  Result = Struct.new(:restored, :error, :open_card, keyword_init: true) do
    def restored?
      restored
    end
  end

  def initialize(card:, actor:, force: false)
    @card = card
    @actor = actor
    @force = force
  end

  def perform
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      @card.lock!
      result = refused(precondition_refusal) || restore!
      raise ActiveRecord::Rollback unless result.restored?
    end
    @card.reload unless result.restored?
    result
  end

  private

  def precondition_refusal
    return NOT_ARCHIVED unless @card.archived?

    PIPELINE_ARCHIVED if @card.pipeline.archived?
  end

  def refused(error)
    Result.new(restored: false, error: error) if error
  end

  def restore!
    Crm::Cards::Closer.new(card: @card, actor: @actor, result: 'reopen', payload_extra: { restored: true }).perform
    conflict = open_sibling if @card.open? && !@force
    return Result.new(restored: false, error: CONFLICT, open_card: conflict) if conflict

    Result.new(restored: true)
  end

  # O card aberto mais antigo do mesmo contato no mesmo funil. Card sem contato não tem como conflitar.
  def open_sibling
    return if @card.contact_id.blank?

    @card.account.crm_cards.open
         .where(pipeline_id: @card.pipeline_id, contact_id: @card.contact_id)
         .where.not(id: @card.id).order(:id).first
  end
end
