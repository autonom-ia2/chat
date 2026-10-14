# Reatribui as reuniões de quem saiu da conta (#1187, J8-A9) fora do callback de remoção do usuário:
# um problema numa reunião nunca pode impedir que alguém seja removido da conta.
class Crm::BookingV2::OrphanReassignJob < ApplicationJob
  queue_as :default

  def perform(account_id, user_id)
    Crm::BookingV2::OrphanReassigner.new(account_id: account_id, user_id: user_id).perform
  end
end
