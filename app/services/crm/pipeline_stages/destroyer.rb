class Crm::PipelineStages::Destroyer
  SUCCESS = :success
  HAS_CARDS = :has_cards
  LAST_STAGE = :last_stage
  # Um registro do banco ainda aponta para a etapa (não um card). Nada foi apagado; a mensagem diz isso, sem culpar cards.
  IN_USE = :in_use

  # actor: quem apagou a etapa, autor da atividade `move` de cada card levado para a etapa escolhida.
  def initialize(stage:, target_stage_id: nil, actor: nil)
    @stage = stage
    @target_stage_id = target_stage_id
    @actor = actor
  end

  # An EMPTY stage (no cards of any status) is deletable from the UI. Two things that used to block it
  # are handled here instead of surfacing as a raw FK violation:
  #   - AI suggestion history and stage automations (with their runs) cascade away (see Crm::PipelineStage).
  #   - If the stage is an inbox's default landing stage, the default is reassigned to a surviving
  #     stage so new conversations keep a valid home.
  # Cards (any status) still block: a card must always point at a real stage. When the caller
  # passes target_stage_id (the delete-stage picker), cards move there first — status untouched,
  # only the stage changes, with the `move` activity and entered_stage_at of each card — so a stage
  # holding only won/lost/archived cards becomes deletable without silently discarding them.
  def perform
    result = nil
    ActiveRecord::Base.transaction do
      # Moving cards and destroying the stage must commit or roll back together — if move
      # succeeded but destroy! then failed (e.g. a race re-attached a card), a card left
      # pointing at the target while the source stage survives would be a silent, permanent
      # side effect of a failed delete.
      move_cards_to_target! if @target_stage_id.present?

      if @stage.cards.exists?
        result = HAS_CARDS
        raise ActiveRecord::Rollback
      end

      if fallback_stage.blank?
        result = LAST_STAGE
        raise ActiveRecord::Rollback
      end

      reassign_default_stage!
      @stage.destroy!
      result = SUCCESS
    end
    result
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
    blocked(e)
  end

  private

  # The whole transaction rolled back (including move_cards_to_target!). A card attached in a race (the cards
  # restrict_with_error callback, or the FK of a concurrent insert) is "has cards"; any other row still pointing at the
  # stage is IN_USE, never blamed on cards.
  def blocked(error)
    return HAS_CARDS if @stage.cards.exists?

    Rails.logger.warn("[crm][stages][destroyer] stage_id=#{@stage.id} blocked: #{error.class} #{error.cause&.class}")
    IN_USE
  end

  # Scoped to the same pipeline (tenant-safety, same pattern as fallback_stage) and excludes
  # the stage itself. A blank/foreign/invalid id is silently a no-op — the exists? check right
  # after this call still catches it and reports HAS_CARDS instead of failing open.
  # Em lote (sem N+1): uma atualização para todos os cards e uma inserção para as atividades. A atividade guarda o nome
  # das duas etapas, porque esta vai deixar de existir. Sem webhook nem conversão de anúncio por card (insert_all não roda
  # callbacks): é a etapa que sumiu, não um avanço do cliente no funil. As automações das etapas também não rodam, como antes.
  def move_cards_to_target!
    target = @stage.pipeline.stages.where.not(id: @stage.id).find_by(id: @target_stage_id)
    return if target.blank?

    # FOR UPDATE: um card movido por outra pessoa enquanto isso espera a trava e, relido, sai da lista (não está mais
    # nesta etapa); os da lista ficam travados até o fim da transação. Só eles mudam e só eles ganham a atividade.
    card_ids = @stage.cards.lock.pluck(:id)
    return if card_ids.empty?

    now = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    Crm::Card.where(id: card_ids, stage_id: @stage.id)
             .update_all(stage_id: target.id, entered_stage_at: now, last_activity_at: now, updated_at: now)
    Crm::Activity.insert_all!(card_ids.map { |card_id| move_activity(card_id, target, now) })
    # rubocop:enable Rails/SkipsModelValidations
  end

  def move_activity(card_id, target, now)
    {
      account_id: @stage.account_id, card_id: card_id, actor_type: @actor ? @actor.class.name.underscore : 'system',
      actor_id: @actor&.id, event_type: 'move', created_at: now,
      payload: { from_pipeline_id: @stage.pipeline_id, to_pipeline_id: target.pipeline_id, from_stage_id: @stage.id,
                 to_stage_id: target.id, from_stage_name: @stage.name, to_stage_name: target.name, motivo: 'etapa_apagada' }
    }
  end

  def fallback_stage
    @fallback_stage ||= @stage.pipeline.stages.where.not(id: @stage.id).order(:position, :id).first
  end

  # Repoint every place that named this stage as the default landing stage to the fallback, so new
  # conversations/cards keep a valid home. These are logical references (some lack a DB FK), scoped to
  # the stage's own account/pipeline so deleting a stage can never touch another tenant's rows.
  # Bulk FK pointer swap — no validations/callbacks to run, so update_all is intentional.
  def reassign_default_stage!
    account_id = @stage.account_id
    fallback_id = fallback_stage.id
    # rubocop:disable Rails/SkipsModelValidations
    Crm::PipelineInbox.where(account_id: account_id, pipeline_id: @stage.pipeline_id, default_stage_id: @stage.id)
                      .update_all(default_stage_id: fallback_id)
    Crm::InboxSetting.where(account_id: account_id, default_stage_id: @stage.id).update_all(default_stage_id: fallback_id)
    Crm::AgentBookingProfile.where(account_id: account_id, default_stage_id: @stage.id).update_all(default_stage_id: fallback_id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
