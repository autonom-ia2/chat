require 'rails_helper'
require 'delegate'

RSpec.describe Instagram::Testers::Invitation do
  subject(:invitation) { described_class.new(client: client, app_id: '10001', target_id: target_id) }

  let(:target_id) { '17841400000000001' }
  let(:client) { instance_double(Instagram::Testers::Client) }
  let(:key) { "instagram_testers:invite:10001:#{target_id}" }

  let(:aof_commands) { instance_spy(Redis) }

  before do
    allow(aof_commands).to receive(:call).with(['WAITAOF', 1, 0, 2000]).and_return([1, 0])
    allow(Instagram::Testers::CoordinationRedis).to receive(:with).and_wrap_original do |original, &block|
      commands = aof_commands
      original.call do |connection|
        wrapper = SimpleDelegator.new(connection)
        wrapper.define_singleton_method(:redis) { commands }
        block.call(wrapper)
      end
    end
    Redis::Alfred.delete("#{key}:lock")
    Redis::Alfred.delete("#{key}:outcome")
  end

  after do
    Redis::Alfred.delete("#{key}:lock")
    Redis::Alfred.delete("#{key}:outcome")
  end

  %w[pending accepted].each do |status|
    it "does not send another invite for #{status}" do
      allow(client).to receive(:status).with(target_id).and_return(status)
      expect(client).not_to receive(:invite)
      expect(invitation.perform).to eq(status: status, invited: false)
    end
  end

  it 'checks status before the invite and suppresses a double submit during role propagation' do
    expect(client).to receive(:status).with(target_id).ordered.and_return('absent')
    expect(Instagram::Testers::CoordinationRedis).to receive(:durable_set)
      .with("#{key}:outcome", kind_of(String), ex: described_class::OUTCOME_TTL).ordered.and_call_original
    expect(aof_commands).to receive(:call).with(['WAITAOF', 1, 0, 2000]).ordered.and_return([1, 0])
    expect(client).to receive(:invite).with(target_id).ordered.and_yield.and_return(true)
    expect(invitation.perform).to eq(status: 'pending', invited: true)
    allow(client).to receive(:status).with(target_id).and_return('absent')
    expect(invitation.perform).to eq(status: 'pending', invited: false)
  end

  it 'retains an ambiguous write and reconciles status without blindly repeating the POST' do
    allow(client).to receive(:status).with(target_id).and_return('absent')
    expect(client).to receive(:invite).once.and_yield.and_raise(Instagram::Testers::Error.new('invite_unknown'))
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
    expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
    allow(client).to receive(:status).with(target_id).and_return('pending')
    expect(invitation.perform).to eq(status: 'pending', invited: false)
  end

  it 'preserves an uncertain marker on request cancellation after sending starts' do
    allow(client).to receive(:status).and_return('absent')
    allow(client).to receive(:invite).and_yield.and_raise(Interrupt, 'Synthetic cancellation')
    expect { invitation.perform }.to raise_error(Interrupt)
    expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
    expect(Redis::Alfred.get("#{key}:lock")).to be_nil
  end

  it 'releases only the lock token it still owns' do
    allow(client).to receive(:status) do
      Redis::Alfred.set("#{key}:lock", 'replacement-token', ex: described_class::LOCK_TTL)
      'accepted'
    end
    invitation.perform
    expect(Redis::Alfred.get("#{key}:lock")).to eq('replacement-token')
  end

  it 'serializes concurrent submissions across accounts sharing the parent app' do
    entered = Queue.new
    release = Queue.new
    allow(client).to receive(:status) do
      entered << true
      release.pop
      'absent'
    end
    expect(client).to receive(:invite).once.and_yield.and_return(true)
    first = Thread.new { invitation.perform }
    entered.pop
    second = described_class.new(client: client, app_id: '10001', target_id: target_id)
    expect { second.perform }.to(raise_error { |error| expect(error.code).to eq('busy') })
    release << true
    expect(first.value).to eq(status: 'pending', invited: true)
  ensure
    release << true if release
    first&.join
  end

  it 'allows another deliberate attempt only after an explicit provider rejection' do
    allow(client).to receive(:status).and_return('absent')
    allow(client).to receive(:invite).and_yield.and_raise(Instagram::Testers::Error.new('invite_rejected', write_rejected: true))
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_rejected') })
    expect(Redis::Alfred.get("#{key}:outcome")).to be_nil
    allow(client).to receive(:invite).and_yield.and_return(true)
    expect(invitation.perform).to eq(status: 'pending', invited: true)
  end

  it 'never sends an invite when the status request fails' do
    allow(client).to receive(:status).and_raise(Instagram::Testers::Error.new('unknown_status'))
    expect(client).not_to receive(:invite)
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'does not send if another worker atomically claims the outcome despite a stale lock' do
    allow(client).to receive(:status).and_return('absent')
    allow(Instagram::Testers::CoordinationRedis).to receive(:get).and_call_original
    allow(Instagram::Testers::CoordinationRedis).to receive(:get).with("#{key}:outcome").and_return(nil)
    Redis::Alfred.set("#{key}:outcome", 'unknown:another-generation', ex: described_class::OUTCOME_TTL)
    expect(client).not_to receive(:invite)
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
  end

  it 'never sends an invite if persisting the unknown claim fails' do
    allow(client).to receive(:status).and_return('absent')
    expect(Instagram::Testers::CoordinationRedis).to receive(:durable_set)
      .with("#{key}:outcome", kind_of(String), ex: described_class::OUTCOME_TTL)
      .and_raise(Redis::BaseError, 'Synthetic claim persistence failure')
    expect(client).not_to receive(:invite)
    expect { invitation.perform }.to raise_error do |error|
      expect(error.code).to eq('invite_unknown')
      expect(error.cause).to be_nil
    end
    expect(Redis::Alfred.get("#{key}:lock")).to be_nil
  end

  it 'does not release an ambiguous write merely because its error code says invite_rejected' do
    allow(client).to receive(:status).and_return('absent')
    expect(client).to receive(:invite).once.and_yield.and_raise(Instagram::Testers::Error.new('invite_rejected'))
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_rejected') })
    expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
  end

  it 'preserves a newer claim when preflight fails in an older attempt' do
    allow(client).to receive(:status).and_return('absent')
    allow(client).to receive(:invite) do
      Redis::Alfred.set("#{key}:outcome", 'unknown:newer-generation', ex: described_class::OUTCOME_TTL)
      raise Instagram::Testers::Error, 'meta_session_expired'
    end
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('meta_session_expired') })
    expect(Redis::Alfred.get("#{key}:outcome")).to eq('unknown:newer-generation')
  end

  it 'reports a failed Redis cleanup rather than hiding it behind a preflight error' do
    allow(client).to receive(:status).and_return('absent')
    allow(client).to receive(:invite).and_raise(Instagram::Testers::Error.new('meta_session_expired'))
    allow(Instagram::Testers::CoordinationRedis).to receive(:delete_if_equals).and_call_original
    expect(Instagram::Testers::CoordinationRedis).to receive(:delete_if_equals).with("#{key}:outcome", kind_of(String))
                                                                               .and_raise(Redis::BaseError, 'Synthetic cleanup failure')
    expect { invitation.perform }.to raise_error do |error|
      expect(error.code).to eq('invite_unknown')
      expect(error.cause).to be_nil
    end
    expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
  end

  context 'with the real Client and synthetic transport' do
    let(:client) { Instagram::Testers::Client.new(configuration: configuration) }
    let(:session) do
      { 'cookie' => 'synthetic=fixture', 'user_agent' => 'Synthetic Client', 'user_id' => '12345',
        'fb_dtsg' => 'synthetic-dtsg', 'lsd' => 'synthetic-lsd', 'jazoest' => '1234' }
    end
    let(:snapshot) { { session: session, version: nil } }
    let(:configuration) do
      instance_double(Instagram::Testers::Configuration, app_id: '10001', business_id: '10002', doc_id: '10003',
                                                         transport_options: { http_proxyaddr: nil, max_retries: 0 })
    end
    let(:roles_url) { 'https://developers.facebook.com/api/graphql/' }
    let(:invite_url) { 'https://developers.facebook.com/apps/10001/async/instagram/roles/add/' }
    let(:absent_body) { '{"data":{"get_app_roles":{"app_roles":[]}}}' }

    before do
      allow(configuration).to receive(:session_snapshot) { snapshot }
      stub_request(:post, roles_url).to_return(status: 200, body: absent_body)
    end

    %w[expired invalidated].each do |reason|
      it "recovers from a session #{reason} between absent status and invite without sending twice" do
        stub_request(:post, roles_url).to_return do
          snapshot[:session] = nil
          snapshot[:version] = reason == 'invalidated' ? 'synthetic-invalidated-version' : nil
          { status: 200, body: absent_body }
        end
        expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('meta_session_expired') })
        expect(a_request(:post, invite_url)).not_to have_been_made
        expect(Redis::Alfred.get("#{key}:outcome")).to be_nil
        snapshot.replace(session: session, version: nil)
        stub_request(:post, roles_url).to_return(status: 200, body: absent_body)
        request = stub_request(:post, invite_url).to_return(status: 200, body: '{"payload":{"success":true}}')
        expect(invitation.perform).to eq(status: 'pending', invited: true)
        expect(invitation.perform).to eq(status: 'pending', invited: false)
        expect(request).to have_been_requested.once
      end
    end

    [Redis::TimeoutError, Redis::CommandError].each do |failure|
      it "blocks the provider POST and retains the claim when WAITAOF raises #{failure}" do
        expect(aof_commands).to receive(:call).with(['WAITAOF', 1, 0, 2000]).once.and_raise(failure, 'Synthetic AOF failure')
        expect { invitation.perform }.to raise_error do |error|
          expect(error.code).to eq('invite_unknown')
          expect(error.cause).to be_nil
        end
        expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
        expect { invitation.perform }.to raise_error(Instagram::Testers::Error)
        expect(a_request(:post, invite_url)).not_to have_been_made
      end
    end

    it 'blocks the provider POST when local fsync is not acknowledged' do
      expect(aof_commands).to receive(:call).with(['WAITAOF', 1, 0, 2000]).and_return([0, 0])
      expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
      expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
      expect(a_request(:post, invite_url)).not_to have_been_made
    end

    it 'retains unknown when the transport loses the write response and never blindly repeats it' do
      request = stub_request(:post, invite_url).to_raise(Net::ReadTimeout.new('Synthetic lost response'))
      expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
      expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
      expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
      expect(request).to have_been_requested.once
    end

    it 'does not release unknown based on provider error strings or a payload containing errors' do
      body = { error: { code: 'invite_rejected', message: 'Synthetic rejection' }, payload: { success: false } }.to_json
      stub_request(:post, invite_url).to_return(status: 200, body: body)
      expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
      expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
    end

    it 'releases its claim on cancellation before the transport starts' do
      expect(configuration).to receive(:transport_options).ordered.and_return(http_proxyaddr: nil, max_retries: 0)
      expect(configuration).to receive(:transport_options).ordered.and_raise(Interrupt, 'Synthetic preflight cancellation')
      expect { invitation.perform }.to raise_error(Interrupt)
      expect(a_request(:post, invite_url)).not_to have_been_made
      expect(Redis::Alfred.get("#{key}:outcome")).to be_nil
      expect(Redis::Alfred.get("#{key}:lock")).to be_nil
    end

    it 'reports a Redis read failure during preflight and releases only its own claim without a POST' do
      expect(configuration).to receive(:session_snapshot).ordered.and_return(snapshot)
      expect(configuration).to receive(:session_snapshot).ordered.and_raise(Redis::BaseError, 'Synthetic session read failure')
      expect { invitation.perform }.to raise_error do |error|
        expect(error.code).to eq('invite_unknown')
        expect(error.cause).to be_nil
      end
      expect(a_request(:post, invite_url)).not_to have_been_made
      expect(Redis::Alfred.get("#{key}:outcome")).to be_nil
    end

    it 'retains unknown on cancellation inside HTTParty after the transport starts' do
      allow(HTTParty).to receive(:post).and_call_original
      expect(HTTParty).to receive(:post).with(invite_url, any_args).and_raise(Interrupt, 'Synthetic transport cancellation')
      expect { invitation.perform }.to raise_error(Interrupt)
      expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
      expect(Redis::Alfred.get("#{key}:lock")).to be_nil
    end

    [401, 403, 407].each do |status|
      it "retains unknown after an HTTP #{status} response despite the recognized public error code" do
        stub_request(:post, invite_url).to_return(status: status)
        code = status == 407 ? 'proxy_unavailable' : 'meta_session_expired'
        expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq(code) })
        expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
        expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
      end
    end
  end
end
