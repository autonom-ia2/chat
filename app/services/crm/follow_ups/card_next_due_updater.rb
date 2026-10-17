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

  # A tarefa de retomar da memória das IAs (#1601, D3) não tem prazo: não é o próximo retorno do card.
  def next_due_at
    @card.follow_ups.active.where("crm_follow_ups.metadata -> 'memoria' IS NULL").order(:due_at).limit(1).pick(:due_at)
  end
end
