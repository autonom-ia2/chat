# A rotina diária do cartão fidelidade (#3100, config/schedule.yml): vence os carimbos que passaram da validade. Cada
# pessoa com entrada vencida e ainda com resto ganha um movimento "venceu" com o que sobrou, e o saldo desce junto, com
# a linha travada (Fidelidade::Carteira#vencer). Rodar de novo não vence nada duas vezes: a entrada vencida fica sem
# resto. Uma pessoa que falha não segura as outras; o erro vai para o log e ela vence na rotina seguinte.
class Fidelidade::VencerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    agora = Time.current
    vencidas = Fidelidade::Movimento.a_vencer(agora).distinct.pluck(:programa_id, :contact_id)
    programas = Fidelidade::Programa.where(id: vencidas.map(&:first).uniq).index_by(&:id)
    vencidas.each { |programa_id, contact_id| vencer(programas[programa_id], contact_id, agora) }
  end

  private

  def vencer(programa, contact_id, agora)
    contato = programa && Contact.where(account_id: programa.account_id).find_by(id: contact_id)
    Fidelidade::Carteira.new(programa, contato).vencer(agora) if contato
  rescue StandardError => e
    Rails.logger.error("[Fidelidade::VencerJob] não venceu programa=#{programa&.id} contato=#{contact_id}: #{e.class}")
  end
end
