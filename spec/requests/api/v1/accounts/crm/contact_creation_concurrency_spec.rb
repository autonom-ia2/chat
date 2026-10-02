require 'rails_helper'
require 'timeout'

RSpec.describe 'CRM concurrent contact creation', :relationships_committed_fixtures, type: :request do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let!(:cards) do
    %w[First Second].map do |title|
      account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: title)
    end
  end
  let(:phone) { '+14155552671' }
  let(:workers) { [] }
  let(:validation_ready) { Queue.new }
  let(:release_validation) { Queue.new }
  let(:requests) do
    contact = { name: 'Concurrent contact', phone_number: phone }
    {
      first_card: ["/api/v1/accounts/#{account.id}/crm/cards/#{cards.first.id}/contact", { contact: contact }],
      second_card: ["/api/v1/accounts/#{account.id}/crm/cards/#{cards.last.id}/contact", { contact: contact }],
      registration: ["/api/v1/accounts/#{account.id}/crm/cards", {
        card: { title: 'Registered opportunity', pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id,
                relationship: { mode: 'new', contact: contact, company: { mode: 'none' } } }
      }]
    }
  end

  let(:validation_barrier) do
    # Stop the winning request after its real identity validation, before INSERT.
    # Without serialization, the other writer can validate and insert the same phone.
    ready = validation_ready
    release = release_validation
    target_phone = phone
    proc do
      if phone_number == target_phone && Thread.current[:crm_pause_contact_validation]
        Thread.current[:crm_pause_contact_validation] = false
        ready << true
        release.pop
      end
    end
  end

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    Contact.set_callback(:validation, :after, validation_barrier)
  end

  after do
    release_validation << true
    workers.each { |worker| worker.join(1) || worker.kill.join }
    Contact.skip_callback(:validation, :after, validation_barrier)
    Crm::Activity.where(account_id: account.id).delete_all
    account.crm_cards.destroy_all
    account.crm_pipelines.destroy_all
    account.contacts.destroy_all
    account.account_users.destroy_all
    IdempotencyKey.where(account: account).delete_all
    account.destroy!
    admin.destroy!
  end

  # Connection/barrier helpers are shared across the three real endpoint races.
  def concurrent_request(operation, headers, pause_validation: false)
    ready = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SET lock_timeout = '5s'")
        ready << connection.select_value('SELECT pg_backend_pid()')
        Thread.current[:crm_pause_contact_validation] = pause_validation
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.post(operation.first, params: operation.last, headers: headers, as: :json)
        [session.response.status, session.response.parsed_body]
      ensure
        Thread.current[:crm_pause_contact_validation] = nil
        connection.execute('SET lock_timeout TO DEFAULT')
      end
    end
    workers << worker
    [worker, Timeout.timeout(10) { ready.pop }]
  end

  def wait_for_serialization(worker, pid, blocker_pid)
    Timeout.timeout(10) do
      loop do
        return true if ActiveRecord::Base.connection.select_value(
          "SELECT #{Integer(blocker_pid)} = ANY(pg_blocking_pids(#{Integer(pid)}))"
        )
        # An unprotected writer finishes instead of waiting; let the assertions
        # expose the duplicate after the first request also commits.
        return false unless worker.alive?

        sleep 0.01
      end
    end
  end

  [[:first_card, :second_card, 422], [:first_card, :registration, 409], [:registration, :first_card, 422]].each do |first, second, conflict_status|
    it "serializes #{first} followed by #{second}, with distinct idempotency keys" do
      first_headers = admin.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid)
      second_headers = admin.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid)
      first_operation = requests.fetch(first)
      second_operation = requests.fetch(second)
      winner, winner_pid = concurrent_request(first_operation, first_headers, pause_validation: true)
      Timeout.timeout(10) { validation_ready.pop }
      loser, loser_pid = concurrent_request(second_operation, second_headers)
      serialized = wait_for_serialization(loser, loser_pid, winner_pid)
      release_validation << true
      expect([winner, loser].map { |worker| worker.join(15) }).to eq([winner, loser])
      expect([winner.value.first, loser.value.first, serialized]).to eq([201, conflict_status, true])
      expect(account.contacts.where(phone_number: phone).count).to eq(1)
      person = account.contacts.find_by!(phone_number: phone)
      expect(account.crm_cards.where.not(contact_id: nil).pluck(:contact_id)).to eq([person.id])
      expect(account.crm_cards.count).to eq(first == :registration ? 3 : 2)
      expect(IdempotencyKey.where(account: account).pluck(:key, :state)).to eq([[first_headers['Idempotency-Key'], 'done']])

      post first_operation.first, params: first_operation.last, headers: first_headers, as: :json
      expect([response.status, response.headers['Idempotency-Replayed'], account.contacts.where(phone_number: phone).count]).to eq([201, 'true', 1])
    end
  end
end
