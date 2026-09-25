# Pesquisa de empresa e decisor de um lead no Sidekiq (#679). O pedido já foi aceito por Research::Queue.enqueue, que
# deixou o lead em queued; este job só roda o que ainda está esperando.
#
# Outra pesquisa da mesma empresa rodando: o lead fica em waiting_capacity e o job volta depois, sem segurar worker
# nem conexão, e reaproveita o que a primeira gravou. Quebra inesperada vira failed (interrupted) sem relançar: o
# Sidekiq refaria uma chamada paga, e o lead falho aceita um pedido novo.
class Autonomia::Prospecting::Research::ResearchJob < ApplicationJob
  queue_as :prospecting

  WAIT_FOR_COMPANY = 30.seconds

  def perform(lead_id, force = false) # rubocop:disable Style/OptionalBooleanParameter -- argumento serializado do ActiveJob
    lead = Autonomia::Prospecting::Lead.find_by(id: lead_id)
    return unless lead && Autonomia::Prospecting::Research::States::RUNNABLE.include?(lead.company_research_status)

    waiting = research(lead, force) == :waiting
    self.class.set(wait: WAIT_FOR_COMPANY).perform_later(lead_id, force) if waiting
    Autonomia::Prospecting::LeadBroadcaster.updated(lead.reload) unless waiting
  end

  private

  def research(lead, force)
    Autonomia::Prospecting::Research::Runner.new(lead: lead, force: force).perform
  rescue StandardError => e
    Rails.logger.warn("[Autonomia::Prospecting::Research::ResearchJob] lead_id=#{lead.id} interrupted error=#{e.class.name}")
    Autonomia::Prospecting::Research::LeadWriter.new(lead).write(
      Autonomia::Prospecting::Research::Outcome.failure('failed', Autonomia::Prospecting::Research::Queue::INTERRUPTED)
    )
    :done
  end
end
