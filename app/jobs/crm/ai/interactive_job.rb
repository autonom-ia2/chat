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
end
