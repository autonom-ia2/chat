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
  # Ganhar ou perder um card arquivado pelo fechar (o /close ou o lote): restaure antes. Reabrir por lá é restaurar.
  CLOSE_ARCHIVED = 'crm.card_close_archived'.freeze

  # A flag das telas (config/features.yml). Com ela desligada, o reabrir antigo (/close e o lote) fica como antes do
  # #2095: a janela antiga não conhece as recusas do restaurar nem a permissão "Arquivar cards".
  FLAG = 'crm_arquivados'.freeze

  Result = Struct.new(:restored, :error, :open_card, keyword_init: true) do
    def restored?
      restored
    end
  end

  # O reabrir do card arquivado pelo fechar (o /close ou o lote) segue as regras do restaurar?
  def self.reabrir_e_restaurar?(card)
    card.archived? && card.account.feature_enabled?(FLAG)
  end

  # Também o lote (Crm::Cards::BulkRestorer), com todos os cards no início, em ordem: dois lotes cruzados (A depois B e
  # B depois A) não fecham ciclo. Pegar de novo a mesma chave na mesma transação não espera.
  def self.travar_contatos_no_funil!(cards)
    chaves = cards.select { |card| card.contact_id.present? }
                  .map { |card| "crm_restore:#{card.account_id}:#{card.contact_id}:#{card.pipeline_id}" }.uniq.sort
    chaves.each do |chave|
      Crm::Card.connection.execute(Crm::Card.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', chave]))
    end
  end

  def initialize(card:, actor:, force: false)
    @card = card
    @actor = actor
    @force = force
  end

  # A trava compartilhada de arquivar da conta vem antes de qualquer trava de linha (ver Crm::Pipelines::TravaDeArquivar).
  def perform
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      Crm::Pipelines::TravaDeArquivar.compartilhar!(@card.account_id)
      travar_funil!
      @card.lock!
      result = refused(precondition_refusal) || restore!
      raise ActiveRecord::Rollback unless result.restored?
    end
    @card.reload unless result.restored?
    result
  end

  private

  # O funil antes do card, como no arquivar do funil (Crm::Pipelines::Archiver: funil, depois cards). FOR SHARE espera um
  # arquivamento em curso deste funil e, depois dele, o status relido decide (PIPELINE_ARCHIVED); sem isto, restaurar
  # enquanto o "Mover" levava os abertos deixava este card aberto no funil que acabou de ser arquivado.
  def travar_funil!
    Crm::Pipeline.where(id: @card.pipeline_id).lock('FOR SHARE').load
    @card.pipeline&.reload
  end

  def precondition_refusal
    return NOT_ARCHIVED unless @card.archived?

    PIPELINE_ARCHIVED if @card.pipeline.archived?
  end

  def refused(error)
    Result.new(restored: false, error: error) if error
  end

  # O card arquivado há tempo pode ter um dono que já saiu da conta: ele volta sem dono (Crm::Card.donos_fora_da_conta),
  # e a atividade guarda quem era.
  def restore!
    payload = { restored: true }
    if @card.dono_saiu_da_conta?
      payload[:dono_que_saiu_id] = @card.owner_id
      @card.owner_id = nil
    end
    travar_contato_no_funil!
    Crm::Cards::Closer.new(card: @card, actor: @actor, result: 'reopen', payload_extra: payload).perform
    conflict = open_sibling if @card.open? && !@force
    return Result.new(restored: false, error: CONFLICT, open_card: conflict) if conflict

    Result.new(restored: true)
  end

  # Dois arquivados do mesmo cliente no mesmo funil restaurados ao mesmo tempo: cada um trava só o próprio card, e
  # nenhum veria o outro aberto. Esta trava (até o fim da transação) põe um depois do outro; o segundo vê o primeiro.
  def travar_contato_no_funil!
    self.class.travar_contatos_no_funil!([@card])
  end

  # O card aberto mais antigo do mesmo contato no mesmo funil. Card sem contato não tem como conflitar.
  def open_sibling
    return if @card.contact_id.blank?

    @card.account.crm_cards.open
         .where(pipeline_id: @card.pipeline_id, contact_id: @card.contact_id)
         .where.not(id: @card.id).order(:id).first
  end
end
