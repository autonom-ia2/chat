require 'rails_helper'
require 'timeout'

RSpec.describe 'MCP message commit and concurrency', :relationships_committed_fixtures, type: :request do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:link) { Autonomia::UserLink.create!(identity_user_id: 'mcp-concurrency-user', user: admin, email: admin.email) }
  let!(:conversation) { create(:conversation, account: account) }
  let!(:integration) do
    Mcp::IntegrationToken.create!(
      account: account, created_by: admin, identity_subject: link.identity_user_id,
      name: 'Concurrent MCP', scopes: Mcp::IntegrationToken::DEFAULT_SCOPES
    )
  end
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }
  let(:headers) { { 'api_access_token' => integration.access_token.token, 'Idempotency-Key' => 'concurrent-message-123' } }
  let(:workers) { [] }
  let(:created) { Queue.new }
  let(:release) { Queue.new }
  let(:pause_after_create) do
    ready = created
    resume = release
    proc do
      if content == 'Concurrent message' && Thread.current[:mcp_pause_message_create]
        ready << true
        resume.pop
      end
    end
  end

  let(:fail_after_commit) do
    proc { raise 'Injected after-commit failure' if content == 'Committed message' }
  end

  before do
    Message.set_callback(:create, :after, pause_after_create)
    Message.set_callback(:commit, :after, fail_after_commit)
  end

  after do
    release << true
    workers.each { |worker| worker.join(1) || worker.kill.join }
    Message.skip_callback(:create, :after, pause_after_create)
    Message.skip_callback(:commit, :after, fail_after_commit)
    IdempotencyKey.where(account: account).delete_all
    integration.revoke!
    account.messages.destroy_all
    account.conversations.destroy_all
    account.contacts.destroy_all
    # Sem transacao, os working_hours das caixas (apagados por destroy_async, que este
    # spec nao executa) ficavam commitados e quebravam specs seguintes
    # (ex.: WorkingHour.today com inbox nil). Apaga explicitamente antes das caixas.
    WorkingHour.where(inbox_id: account.inboxes.select(:id)).delete_all
    account.inboxes.destroy_all
    account.account_users.destroy_all
    account.notification_settings.destroy_all
    account.destroy!
    admin.destroy!
  end

  it 'serializes two real requests with the same key and replays one committed message' do
    target_path = path
    request_headers = headers
    pids = Queue.new

    2.times do |index|
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pids << connection.select_value('SELECT pg_backend_pid()')
          Thread.current[:mcp_pause_message_create] = index.zero?
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.post target_path, params: { content: 'Concurrent message' }, headers: request_headers, as: :json
          [session.response.status, session.response.parsed_body.fetch('id'), session.response.headers['Idempotency-Replayed']]
        ensure
          Thread.current[:mcp_pause_message_create] = nil
          Current.reset
        end
      end
      Timeout.timeout(10) { created.pop } if index.zero?
    end

    winner_pid = Timeout.timeout(10) { pids.pop }
    loser_pid = Timeout.timeout(10) { pids.pop }
    Timeout.timeout(10) do
      until ActiveRecord::Base.connection.select_value(
        "SELECT #{Integer(winner_pid)} = ANY(pg_blocking_pids(#{Integer(loser_pid)}))"
      )
        raise 'Duplicate request did not wait for the uncommitted claim' unless workers.last.alive?

        sleep 0.01
      end
    end
    release << true

    expect(workers.map { |worker| worker.join(15) }).to eq(workers)
    responses = workers.map(&:value)
    expect(responses.map(&:first)).to eq([200, 200])
    expect(responses.map { |result| result[1] }.uniq.length).to eq(1)
    expect(responses.last[2]).to eq('true')
    expect(conversation.messages.where(content: 'Concurrent message').count).to eq(1)
    expect(IdempotencyKey.where(account: account).pluck(:state)).to eq(['done'])
    expect(enqueued_jobs.count { |job| job[:job] == SendReplyJob && job[:args].first == responses.first[1] }).to eq(1)
  end

  it 'recovers the committed response even if an after-commit callback fails' do
    post path, params: { content: 'Committed message' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    message = conversation.messages.find_by!(content: 'Committed message')
    expect(IdempotencyKey.find_by!(account: account)).to be_done

    post path, params: { content: 'Committed message' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(message.id)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(conversation.messages.where(content: 'Committed message').count).to eq(1)
  end
end
