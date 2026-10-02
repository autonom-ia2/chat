# Explicit local probe: real commits and concurrent HTTP requests, not transactional fixtures.
# Run only with the dedicated scratch database named below and an isolated Redis.
require 'uri'
require 'timeout'
require 'json'

url = URI.parse(ENV.fetch('DATABASE_URL', ''))
abort 'Explicit scratch test environment required' unless ENV['RAILS_ENV'] == 'test' &&
                                                          %w[localhost 127.0.0.1].include?(url.host) &&
                                                          url.path == '/chat2you_792_probe_test'
abort 'Dedicated loopback Redis required' unless ENV['REDIS_URL'] == 'redis://127.0.0.1:6792/1'
$LOAD_PATH.unshift(File.expand_path('..', __dir__))
require 'rails_helper'

config = ActiveRecord::Base.connection_db_config
abort 'Dedicated loopback test database required' unless Rails.env.test? && config.database == 'chat2you_792_probe_test' &&
                                                         %w[localhost 127.0.0.1].include?(config.configuration_hash[:host])
abort 'Use an empty scratch database' if Account.exists?

helpers = Object.new.extend(CrmHelpers)
ActiveJob::Base.queue_adapter = :test
ActionMailer::Base.delivery_method = :test
ENV['CRM_KANBAN_ENABLED'] = 'true'

account = FactoryBot.create(:account)
admin = FactoryBot.create(:user, account: account, role: :administrator)
pipeline, stage = helpers.create_crm_pipeline(account: account, user: admin)
base_headers = helpers.auth_headers(admin)
observations = Queue.new
Contact.after_create_commit do
  next unless name.start_with?('CRM probe')

  linked_card = Crm::Card.find_by(contact_id: id)
  captured = IdempotencyKey.where(account_id: account_id, state: :done).any? do |record|
    record.response_body.dig('payload', 'contact_id') == id
  end
  observations << { linked: linked_card.present?, response_captured: captured }
end

parallel_requests = lambda do |path, mode|
  shared_key = SecureRandom.uuid
  ready = Queue.new
  start = Queue.new
  workers = Array.new(2) do |index|
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        key = mode == 'same_key' ? shared_key : SecureRandom.uuid
        ready << true
        start.pop
        session.post path, params: { contact: { name: 'CRM probe concurrent' } },
                           headers: base_headers.merge('Idempotency-Key' => key), as: :json
        { index: index, status: session.response.status, replayed: session.response.headers['Idempotency-Replayed'] == 'true' }
      end
    end
  end
  Timeout.timeout(30) do
    2.times { ready.pop }
    2.times { start << true }
    workers.map(&:value)
  end
end

results = []
%w[same_key different_keys].each do |mode|
  card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: admin, title: "Probe #{mode}")
  path = "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/contact"
  before = [Contact.count, Crm::Card.count, Crm::Activity.count, IdempotencyKey.count]
  responses = parallel_requests.call(path, mode)
  expected = mode == 'same_key' ? [201, 201] : [201, 422]
  raise "Unexpected responses: #{responses.inspect}" unless responses.pluck(:status).sort == expected

  after = [Contact.count, Crm::Card.count, Crm::Activity.count, IdempotencyKey.count]
  raise 'Concurrent request left partial/duplicate records' unless after.zip(before).map { |a, b| a - b } == [1, 0, 1, 1]
  raise 'Retry did not replay the stored response' if mode == 'same_key' && responses.count { |r| r[:replayed] } != 1

  observation = observations.pop
  raise 'Contact callback ran before the link/response was committed' unless observation.values.all?
  raise 'Wrong card linkage' if card.reload.contact_id.nil?

  results << { scenario: mode, passed: true, responses: responses, record_delta: [1, 0, 1, 1], after_commit: observation }
end

# An exception while capturing the successful response must roll back the contact,
# link, audit, claim and all after_commit notifications. The same key can then retry.
card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: admin, title: 'Probe rollback')
path = "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/contact"
failure_key = SecureRandom.uuid
body = { contact: { name: 'CRM probe rollback' } }
headers = base_headers.merge('Idempotency-Key' => failure_key)
before = [Contact.count, Crm::Activity.count, IdempotencyKey.count]
failure = proc { raise 'controlled response capture failure' if key == failure_key && done? }
IdempotencyKey.set_callback(:update, :before, failure)
session = ActionDispatch::Integration::Session.new(Rails.application)
begin
  session.post path, params: body, headers: headers, as: :json
  raise 'Expected failure was not returned' unless session.response.status == 500
rescue RuntimeError => e
  raise unless e.message == 'controlled response capture failure'
ensure
  IdempotencyKey.skip_callback(:update, :before, failure)
end
raise 'Failed response capture left records' unless before == [Contact.count, Crm::Activity.count, IdempotencyKey.count]
raise 'Failed transaction changed the card' if card.reload.contact_id.present?
raise 'Failed transaction ran after_commit callbacks' unless observations.empty?

session.post path, params: body, headers: headers, as: :json
raise 'The failed key cannot be retried' unless session.response.status == 201
raise 'Retry callback preceded persistence' unless observations.pop.values.all?

results << { scenario: 'response_capture_rollback_then_retry', passed: true, retry_status: session.response.status }

puts JSON.pretty_generate({ database: config.database, all_passed: true, checks: results })
