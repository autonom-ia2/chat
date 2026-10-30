require 'rails_helper'

RSpec.describe Crm::MetaAds::PageSubscription do
  subject(:subscription) { described_class.new(page_id: page_id, access_token: token, api_version: 'v22.0') }

  let(:page_id) { '1234567890' }
  let(:token) { 'page-token-not-a-real-secret' }
  let(:app_id) { '544486745144318' }
  let(:url) { "https://graph.facebook.com/v22.0/#{page_id}/subscribed_apps" }

  before do
    stub_request(:get, 'https://graph.facebook.com/v22.0/app').with(headers: { 'Authorization' => "Bearer #{token}" })
                                                              .to_return(status: 200, body: { id: app_id }.to_json,
                                                                         headers: { 'Content-Type' => 'application/json' })
  end

  def stub_current(apps)
    stub_request(:get, url).with(headers: { 'Authorization' => "Bearer #{token}" })
                           .to_return(status: 200, body: { data: apps }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # Uma resposta por leitura, na ordem: antes da escrita e a releitura que confere.
  def stub_reads(*lists)
    stub_request(:get, url).with(headers: { 'Authorization' => "Bearer #{token}" })
                           .to_return(*lists.map do |fields|
                             { status: 200, body: { data: [{ id: app_id, subscribed_fields: fields }] }.to_json,
                               headers: { 'Content-Type' => 'application/json' } }
                           end)
  end

  def stub_post(fields)
    stub_request(:post, url).with(body: { subscribed_fields: fields.join(',') }, headers: { 'Authorization' => "Bearer #{token}" })
                            .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#fields' do
    it 'returns only the fields of the app that owns the token, never another app of the page' do
      stub_current([{ id: '1', subscribed_fields: ['feed'] }, { id: app_id, subscribed_fields: %w[messages leadgen] }])

      expect(subscription.fields).to eq(%w[messages leadgen])
    end

    it 'returns an empty list when the app is not subscribed to the page' do
      stub_current([])

      expect(subscription.fields).to eq([])
    end
  end

  describe '#add!' do
    it 'posts the union of the current fields and the new ones' do
      stub_reads(%w[messages feed], %w[messages feed leadgen])
      post = stub_post(%w[messages feed leadgen])

      subscription.add!(%w[leadgen])

      expect(post).to have_been_requested
    end

    it 'does not post when every field is already subscribed' do
      stub_current([{ id: app_id, subscribed_fields: %w[leadgen feed] }])

      subscription.add!(%w[leadgen])

      expect(a_request(:post, url)).not_to have_been_made
    end
  end

  describe '#remove!' do
    it 'posts the fields that remain' do
      stub_reads(%w[messages leadgen feed], %w[messages feed])
      post = stub_post(%w[messages feed])

      subscription.remove!(%w[leadgen])

      expect(post).to have_been_requested
    end

    it 'removes the app from the page when no field remains' do
      stub_reads(%w[leadgen], [])
      delete = stub_request(:delete, url).with(headers: { 'Authorization' => "Bearer #{token}" })
                                         .to_return(status: 200, body: { success: true }.to_json)

      subscription.remove!(%w[leadgen])

      expect(delete).to have_been_requested
      expect(a_request(:post, url)).not_to have_been_made
    end

    it 'does nothing when the fields are not subscribed' do
      stub_current([{ id: app_id, subscribed_fields: %w[feed] }])

      subscription.remove!(%w[leadgen])

      expect(a_request(:post, url)).not_to have_been_made
      expect(a_request(:delete, url)).not_to have_been_made
    end
  end

  it 'reads nothing from config: with no token app, it never writes another app fields over this one' do
    stub_request(:get, url).to_return(
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: [{ id: '999', subscribed_fields: %w[leadgen feed] }] }.to_json },
      { status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { data: [{ id: '999', subscribed_fields: %w[leadgen feed] }, { id: app_id, subscribed_fields: %w[messages] }] }.to_json }
    )
    post = stub_post(%w[messages])

    subscription.add!(%w[messages])

    expect(post).to have_been_requested
    expect(subscription.fields).to eq(%w[messages])
  end

  describe 'concurrent writers on the same page (#2200)' do
    let(:lock_key) { described_class.lock_key(page_id) }

    around do |example|
      Redis::Alfred.delete(lock_key)
      example.run
    ensure
      Redis::Alfred.delete(lock_key)
    end

    # Uma Página falsa em memória, direto no HTTParty (o WebMock responde um pedido por vez e esconderia a corrida). A
    # leitura demora o bastante para dois escritores sem trava lerem a mesma lista e um apagar o campo do outro.
    # No teste o Redis é o MockRedis, cujo SET NX lê e grava em dois passos; o RedisDeTesteSerializado
    # (config/initializers/01_redis_compartilhado_no_teste.rb) passa cada comando por um Monitor, e o SET NX fica
    # atômico entre threads como no Redis real.
    def fake_page(initial)
      store = { fields: initial, posts: 0 }
      mutex = Mutex.new
      reply = ->(body) { instance_double(HTTParty::Response, success?: true, code: 200, parsed_response: body) }
      allow(HTTParty).to receive(:public_send) do |verb, request_url, **options|
        next reply.call({ 'id' => app_id }) if request_url.end_with?('/app')

        if verb == :post
          mutex.synchronize do
            store[:posts] += 1
            store[:fields] = options[:body][:subscribed_fields].split(',')
          end
          next reply.call({ 'success' => true })
        end

        current = mutex.synchronize { store[:fields].dup }
        sleep(0.1)
        reply.call({ 'data' => [{ 'id' => app_id, 'subscribed_fields' => current }] })
      end
      store
    end

    it 'keeps both fields when two writers subscribe the same page at the same time, with no write lost on the way' do
      store = fake_page(%w[messages])

      [%w[leadgen], %w[feed]].map do |field|
        Thread.new { described_class.new(page_id: page_id, access_token: token, api_version: 'v22.0').add!(field) }
      end.each(&:join)

      expect(store[:fields]).to include('messages', 'leadgen', 'feed')
      expect(store[:posts]).to eq(2) # sem a trava, um apaga o campo do outro e a releitura precisa gravar de novo
    end

    it 'holds the page lock while it writes' do
      held = nil
      stub_reads(%w[feed], %w[feed leadgen])
      stub_request(:post, url).to_return do
        held = Redis::Alfred.exists?(lock_key)
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { success: true }.to_json }
      end

      subscription.add!(%w[leadgen])

      expect(held).to be(true)
    end

    it 'writes again when another writer dropped the field between the POST and the check' do
      stub_reads(%w[messages feed], %w[messages feed], %w[messages feed leadgen])
      post = stub_post(%w[messages feed leadgen])

      subscription.add!(%w[leadgen])

      expect(post).to have_been_requested.twice
    end

    it 'raises a transient error when the page never keeps the field' do
      stub_reads(%w[feed], %w[feed], %w[feed])
      stub_post(%w[feed leadgen])

      expect { subscription.add!(%w[leadgen]) }.to raise_error(described_class::Error) { |error| expect(error).to be_transient }
    end

    it 'waits for the page lock and gives up with a transient error, without writing' do
      stub_const("#{described_class}::LOCK_WAIT", 0.3.seconds)
      Redis::Alfred.set(lock_key, 'outro-processo', nx: true, ex: 10)
      stub_reads(%w[feed])

      expect { subscription.add!(%w[leadgen]) }.to raise_error(described_class::Error) { |error| expect(error).to be_transient }
      expect(a_request(:post, url)).not_to have_been_made
      expect(Redis::Alfred.get(lock_key)).to eq('outro-processo')
    end

    it 'uses the key declared in Redis::RedisKeys and expires it with the TTL while it writes' do
      ttl = nil
      stub_reads(%w[feed], %w[feed leadgen])
      stub_request(:post, url).to_return do
        ttl = Redis::Alfred.ttl(lock_key)
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { success: true }.to_json }
      end

      subscription.add!(%w[leadgen])

      expect(lock_key).to eq(format(Redis::RedisKeys::META_PAGE_SUBSCRIPTION_MUTEX, page_id: page_id))
      expect(ttl).to be_between(1, described_class::LOCK_TTL.to_i)
    end

    it 'takes the lock once the lock of a dead writer expires' do
      stub_const("#{described_class}::LOCK_WAIT", 3.seconds)
      Redis::Alfred.with { |conn| conn.set(lock_key, 'processo-morto', px: 300) }
      stub_reads(%w[feed], %w[feed leadgen])
      post = stub_post(%w[feed leadgen])
      allow(Redis::Alfred).to receive(:set).and_call_original

      subscription.add!(%w[leadgen])

      expect(Redis::Alfred).to have_received(:set).with(lock_key, anything, nx: true, ex: described_class::LOCK_TTL.to_i).at_least(:twice)
      expect(post).to have_been_requested
    end

    it 'never releases a lock that is no longer its own (its TTL ran out and another writer took it)' do
      stub_reads(%w[feed], %w[feed leadgen])
      stub_request(:post, url).to_return do
        Redis::Alfred.set(lock_key, 'outro-processo')
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { success: true }.to_json }
      end

      subscription.add!(%w[leadgen])

      expect(Redis::Alfred.get(lock_key)).to eq('outro-processo')
    end

    it 'turns a Redis failure on the lock into a transient error, without writing' do
      [Redis::CannotConnectError, ConnectionPool::TimeoutError].each do |failure|
        allow(Redis::Alfred).to receive(:set).and_raise(failure)

        expect { subscription.add!(%w[leadgen]) }.to raise_error(described_class::Error) { |error| expect(error).to be_transient }
      end
      expect(a_request(:any, url)).not_to have_been_made
    end

    it 'keeps the result of the write when releasing the lock fails' do
      stub_reads(%w[feed], %w[feed leadgen])
      post = stub_post(%w[feed leadgen])
      allow(Redis::Alfred).to receive(:delete_if_equals).and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:warn)

      expect { subscription.add!(%w[leadgen]) }.not_to raise_error
      expect(post).to have_been_requested
      expect(Rails.logger).to have_received(:warn).with(/lock release failed: Redis::CannotConnectError/)
    end

    it 'logs when another writer changed the page between its write and the check' do
      stub_reads(%w[messages], %w[messages leadgen feed])
      stub_post(%w[messages leadgen])
      allow(Rails.logger).to receive(:warn)

      subscription.add!(%w[leadgen])

      expect(Rails.logger).to have_received(:warn).with(/read differs from write: wrote leadgen,messages, read feed,leadgen,messages/)
    end

    it 'releases the page lock after writing and after failing' do
      stub_reads(%w[feed], %w[feed leadgen])
      stub_post(%w[feed leadgen])
      subscription.add!(%w[leadgen])
      expect(Redis::Alfred.exists?(lock_key)).to be(false)

      stub_request(:get, url).to_return(status: 500, body: '{}')
      expect { described_class.new(page_id: page_id, access_token: token, api_version: 'v22.0').add!(%w[feed]) }
        .to raise_error(described_class::Error)
      expect(Redis::Alfred.exists?(lock_key)).to be(false)
    end
  end

  it 'turns an unreadable answer into a transient error without the token' do
    stub_request(:get, url).to_return(status: 200, body: '{not json', headers: { 'Content-Type' => 'application/json' })

    expect { subscription.fields }.to raise_error(described_class::Error) { |error|
      expect(error).to be_transient
      expect(error.message).not_to include(token)
    }
  end

  it 'raises with the Meta error code and never the token' do
    stub_request(:get, url).to_return(
      status: 400, headers: { 'Content-Type' => 'application/json' },
      body: { error: { code: 190, message: "Invalid OAuth access token #{token}abcdefghij" } }.to_json
    )

    expect { subscription.fields }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq(190)
      expect(error).not_to be_transient
      expect(error.message).not_to include(token)
    }
  end

  it 'marks a usage limit as transient' do
    stub_request(:get, url).to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                                      body: { error: { code: 4, message: 'Application request limit reached' } }.to_json)

    expect { subscription.fields }.to raise_error(described_class::Error) { |error| expect(error).to be_transient }
  end

  it 'marks a network failure as transient' do
    stub_request(:get, url).to_timeout

    expect { subscription.fields }.to raise_error(described_class::Error) { |error| expect(error).to be_transient }
  end

  it 'marks a missing permission as a refusal' do
    stub_request(:get, url).to_return(status: 403, headers: { 'Content-Type' => 'application/json' },
                                      body: { error: { code: 200, message: 'Permissions error' } }.to_json)

    expect { subscription.fields }.to raise_error(described_class::Error) { |error| expect(error).not_to be_transient }
  end
end
