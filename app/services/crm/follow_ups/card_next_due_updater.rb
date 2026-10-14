class Crm::FollowUps::CardNextDueUpdater
  # Lembrete sem card (#1461): nada a atualizar.
  def self.update(card)
    return if card.nil?

    new(card).perform
  end

  def initialize(card)
    @card = card
  end

  def perform
    @card.update!(next_follow_up_at: next_due_at)
  end

  private

  def next_due_at
    @card.follow_ups.active.order(:due_at).limit(1).pick(:due_at)
  end
end
