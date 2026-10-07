# Runs one template import (#1099, delivery B). Takes the import's lock first: a duplicate job, or one that arrives
# while another worker holds a lock that has not expired, does nothing. Failures are stored on the import by Run, so
# Sidekiq never retries it; a worker that dies is taken back by the next claim or by the screen asking for news.
class EmailCampaigns::Import::RunJob < ApplicationJob
  queue_as :medium

  def perform(import_id)
    import = EmailCampaignTemplateImport.find_by(id: import_id)
    token = import&.claim!
    return if token.nil?

    EmailCampaigns::Import::Run.call(import, token)
  end
end
