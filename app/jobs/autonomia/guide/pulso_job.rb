# O pulso do Guia (#935). Sem conta, espalha: um job por conta que tem vigia ligada e um administrador
# ativo, na fila `low`, com uma espera aleatória para as contas não medirem todas no mesmo segundo.
# Com conta, mede aquela (`Pulso`). Roda a cada 15 minutos (`config/schedule.yml`) e quando um sinal
# empurrado antecipa (`Pulso.agora`).
class Autonomia::Guide::PulsoJob < ApplicationJob
  queue_as :low

  ESPALHAR_EM = 5.minutes.to_i

  def perform(account_id = nil)
    return espalhar if account_id.nil?

    account = Account.find_by(id: account_id)
    return unless account&.active? && ::Autonomia::Guide::Seed.eligible?(account)

    ::Autonomia::Guide::Pulso.new(account).perform
  end

  private

  def espalhar
    ::Autonomia::Guide::Pulso.contas.each do |account_id|
      self.class.set(wait: rand(ESPALHAR_EM).seconds).perform_later(account_id)
    end
  end
end
