class Crm::Ai::InteractiveJob < ApplicationJob
  queue_as :medium

  # Repetir o job inteiro pode repetir ferramentas; só o cliente HTTP tem retries.
  discard_on StandardError do |job, error|
    Rails.logger.error("[crm][ai][interactive] request=#{job.arguments.first} error=#{error.class.name}")
    Crm::Ai::InteractiveRequest.finish(job.arguments.first, status: 'failed')
  end

  def perform(id)
    data = Crm::Ai::InteractiveRequest.read(id)
    return unless data && data['status'] == 'pending'

    log_queue_wait(id, data['operation'])
    return unless Crm::Ai::InteractiveRequest.claim(id)

    operation = Crm::Ai::InteractiveOperation.new(data)
    operation.authorize!
    Current.account = operation.context[:account]
    Current.account_user = operation.context[:account_user]
    Current.user = operation.context[:user]
    result = I18n.with_locale(data.fetch('locale')) { operation.perform }
    Crm::Ai::InteractiveRequest.finish(id, status: 'done', result: result)
  ensure
    Current.reset
  end

  private

  # #1367 — quanto o pedido esperou na fila antes de começar (enqueued_at → perform). Só o nome da operação,
  # nunca as entradas. Vazio quando o job rodou sem passar pela fila (perform_now).
  def log_queue_wait(id, operation)
    wait_ms = enqueued_at && ((Time.current - enqueued_at) * 1000).round
    Rails.logger.info("[crm][ai][interactive] start request=#{id} operation=#{operation} queue_wait_ms=#{wait_ms}")
  end
end
