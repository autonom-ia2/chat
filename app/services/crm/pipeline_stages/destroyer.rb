class Crm::PipelineStages::Destroyer
  SUCCESS = :success
  HAS_CARDS = :has_cards
  LAST_STAGE = :last_stage

  def initialize(stage:, target_stage_id: nil)
    @stage = stage
    @target_stage_id = target_stage_id
  end

  # An EMPTY stage (no cards of any status) is deletable from the UI. Two things that used to block it
  # are handled here instead of surfacing as a raw FK violation:
  #   - AI suggestion history cascades away (see Crm::PipelineStage associations).
  #   - If the stage is an inbox's default landing stage, the default is reassigned to a surviving
  #     stage so new conversations keep a valid home.
  # Cards (any status) still block: a card must always point at a real stage. When the caller
  # passes target_stage_id (the delete-stage picker), cards move there first — status untouched,
  # only stage_id changes — so a stage holding only won/lost/archived cards becomes deletable
  # without silently discarding them.
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
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    # Race: a card was attached to the stage between the cards.exists? check and destroy!.
    # The cards restrict_with_error callback raises RecordNotDestroyed; a concurrent FK insert
    # raises InvalidForeignKey. Either way the whole transaction rolls back (including any
    # move_cards_to_target!) and the stage still owns a card — report it as such.
    HAS_CARDS
  end

  private

  # Scoped to the same pipeline (tenant-safety, same pattern as fallback_stage) and excludes
  # the stage itself. A blank/foreign/invalid id is silently a no-op — the exists? check right
  # after this call still catches it and reports HAS_CARDS instead of failing open.
  def move_cards_to_target!
    target = @stage.pipeline.stages.where.not(id: @stage.id).find_by(id: @target_stage_id)
    return if target.blank?

    # rubocop:disable Rails/SkipsModelValidations
    @stage.cards.update_all(stage_id: target.id)
    # rubocop:enable Rails/SkipsModelValidations
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
