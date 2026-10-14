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
      # Só a vez futura é refeita; a que já venceu e espera o DueProcessor ainda avisa.
      @series.follow_ups.pending.where('due_at > ?', Time.current).destroy_all
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
      Crm::FollowUps::RecipientParams.new(account: @series.account, card: @series.card, attributes: @attributes, user: @user).perform
    )
  end

  def recurrence_changes
    raw = @attributes[:recurrence].to_h.with_indifferent_access.compact_blank
    return {} if raw.empty?

    # O que não veio continua como está (mudar só a frequência não apaga o fim escolhido).
    Crm::FollowUps::Creator.recurrence_attributes(current_rule.merge(raw))
  end

  def current_rule
    @series.slice(:frequency, :weekdays, :weekdays_only, :ends_mode, :ends_on, :occurrences_count).with_indifferent_access
  end

  def after_change
    card = @series.card
    Crm::FollowUps::CardNextDueUpdater.update(card)
    Crm::ActivityLogger.new(card: card, actor: @user, event_type: 'follow_up_series_updated',
                            payload: { series_id: @series.id, title: @series.title }).perform
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
  end
end
