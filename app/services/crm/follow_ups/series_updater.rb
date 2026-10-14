# #1460 — "Mudar: esta e todas as próximas". A regra nova vale da próxima vez em diante: a vez que ainda não
# aconteceu é refeita com a regra nova e o que já passou não muda. ("Só a próxima" é o PATCH da própria vez.)
class Crm::FollowUps::SeriesUpdater
  FIELDS = %i[title description timezone].freeze

  def initialize(series:, user:, attributes:)
    @series = series
    @user = user
    @attributes = attributes.to_h.with_indifferent_access
  end

  def perform
    @series.transaction do
      @series.update!(changes_for_series)
      @series.follow_ups.pending.destroy_all
      Crm::FollowUps::SeriesMaterializer.new(@series).perform
    end
    after_change
    @series
  end

  private

  def changes_for_series
    changes = @attributes.slice(*FIELDS)
    changes[:starts_at] = @attributes[:due_at] if @attributes[:due_at].present?
    changes.merge(recurrence_changes).merge(
      Crm::FollowUps::RecipientParams.new(account: @series.account, card: @series.card, attributes: @attributes).perform
    )
  end

  def recurrence_changes
    raw = @attributes[:recurrence].to_h.with_indifferent_access
    return {} if raw[:frequency].blank?

    Crm::FollowUps::Creator.recurrence_attributes(raw)
  end

  def after_change
    card = @series.card
    Crm::FollowUps::CardNextDueUpdater.update(card)
    Crm::ActivityLogger.new(card: card, actor: @user, event_type: 'follow_up_series_updated',
                            payload: { series_id: @series.id, title: @series.title }).perform
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
  end
end
