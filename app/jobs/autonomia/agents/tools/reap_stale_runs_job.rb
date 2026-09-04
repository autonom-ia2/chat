# VARREDOR das execuções assíncronas que ficaram penduradas (#313).
#
# Uma execução avança porque um job se re-agenda. Se essa corrente se rompe — o worker morreu entre
# o aceite e o despacho (um deploy basta: o Sidekiq desta instalação tem `:timeout: 25`), ou o
# `perform_later` falhou porque o Redis estava fora — a linha fica viva para sempre: nunca
# finalizada, nunca recolhida, e o cliente esperando uma cotação que ninguém vai fazer.
#
# Este job é o único ponto que enxerga isso. Ele NÃO retoma a execução: retomar significaria cotar
# de novo no portal, e não há como saber o que já aconteceu lá. Ele fecha a linha e avisa o cliente
# uma vez, com a frase da própria ferramenta — melhor uma resposta honesta do que silêncio.
class Autonomia::Agents::Tools::ReapStaleRunsJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH_LIMIT = 500
  # Folga sobre o prazo da execução: só recolhe o que já passou do `expires_at` com margem, para
  # nunca competir com um poll legítimo que está prestes a rodar.
  GRACE = 5.minutes
  # Uma execução `pending` que nunca foi promovida não tem `expires_at`. Cai por idade.
  PENDING_MAX_AGE = 1.hour

  def perform
    reap_running
    reap_pending
  end

  private

  def reap_running
    ::Autonomia::Agents::ToolRun.where(status: 'running')
                                .where(expires_at: ...GRACE.ago)
                                .limit(BATCH_LIMIT).each { |run| close(run) }
  end

  # `pending` nunca falou com o portal e nunca prometeu nada ao cliente: descarta em silêncio.
  def reap_pending
    ::Autonomia::Agents::ToolRun.where(status: 'pending')
                                .where(created_at: ...PENDING_MAX_AGE.ago)
                                .limit(BATCH_LIMIT).each(&:discard!)
  end

  def close(run)
    native = ::Autonomia::Agents::Tools::Registry.find(run.slug)
    tell_customer(run, native) if native.present? && run.delivered_count.zero?
    run.finish!('failed', failure_code: 'execucao_abandonada')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] reap failed run=#{run.id} #{e.class}")
    nil
  end

  # Força a publicação: a cadeia de entrega humanizada daquele turno já morreu há muito, e esperar
  # por ela deixaria o cliente sem desfecho para sempre.
  def tell_customer(run, native)
    ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(native.failure_message)
  end
end
