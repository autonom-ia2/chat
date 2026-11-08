class Crm::FollowUps::CardNextDueUpdater
  # Lembrete sem card (#1461): nada a atualizar.
  # validar: false (#2096, Crm::Meetings::CancelService ao excluir o contato): grava só a data, mesmo com o card que não
  # passa mais na validação (dono que saiu da conta).
  def self.update(card, validar: true)
    return if card.nil?

    new(card, validar: validar).perform
  end

  def initialize(card, validar: true)
    @card = card
    @validar = validar
  end

  def perform
    @card.next_follow_up_at = next_due_at
    @card.save!(validate: @validar)
  end

  private

  def next_due_at
    @card.follow_ups.active.order(:due_at).limit(1).pick(:due_at)
  end
end
