class Crm::Ai::InteractiveJob < ApplicationJob
  queue_as :medium

  # Repetir o job inteiro pode repetir ferramentas; só o cliente HTTP tem retries.
  discard_on StandardError do |job, error|
    Rails.logger.error("[crm][ai][interactive] request=#{job.arguments.first} error=#{error.class.name}")
    Crm::Ai::InteractiveRequest.finish(job.arguments.first, status: 'failed')
  end

  def perform(id)
    operation = nil
    data = pending_request(id)
    return unless data

    operation = authorized_operation(data)
    result = I18n.with_locale(data.fetch('locale')) { operation.perform }
    unless Crm::Ai::InteractiveRequest.pending?(id)
      record_stale_operation(operation)
      return
    end

    finish_operation(id, operation, result)
  rescue StandardError
    operation&.record_agent_test_failure!
    raise
  ensure
    Current.reset
  end

  private

  def pending_request(id)
    data = Crm::Ai::InteractiveRequest.read(id)
    return unless data && data['status'] == 'pending'
    return unless Crm::Ai::InteractiveRequest.claim(id)

    data
  end

  def authorized_operation(data)
    operation = Crm::Ai::InteractiveOperation.new(data)
    operation.authorize!
    apply_request_context(operation)
    operation
  end

  def apply_request_context(operation)
    Current.account = operation.context[:account]
    Current.account_user = operation.context[:account_user]
    Current.user = operation.context[:user]
  end

  def finish_operation(id, operation, result)
    result = operation.record_agent_test_result!(result)
    finished = Crm::Ai::InteractiveRequest.finish(id, status: 'done', result: result)
    record_stale_operation(operation) if !finished && operation.test_agent
  end

  def record_stale_operation(operation)
    operation.record_agent_test_failure!(completion: 'stale')
  end
end
