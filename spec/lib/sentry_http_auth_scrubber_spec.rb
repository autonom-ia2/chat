require 'spec_helper'
require 'sentry-ruby'
require 'rack'
require 'stringio'
require 'pathname'
require 'climate_control'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/exclude'
require_relative '../../lib/sentry_http_auth_scrubber'

RSpec.describe SentryHttpAuthScrubber do
  let(:secrets) do
    {
      access_token: 'synthetic-aaa', client_secret: 'synthetic-bbb',
      code: 'synthetic-ccc', state: 'synthetic-ddd',
      refresh_token: 'synthetic-eee', appsecret_proof: 'synthetic-fff',
      fb_dtsg: 'synthetic-ggg', lsd: 'synthetic-hhh', signed_request: 'synthetic-iii'
    }
  end
  let(:query) { URI.encode_www_form(secrets.merge(fields: 'id,username', grant_type: 'ig_exchange_token')) }
  let(:url) { "https://graph.instagram.com/access_token?#{query}" }
  let(:logs) { StringIO.new }
  let(:transport_class) do
    Class.new(Sentry::Transport) do
      attr_reader :payloads

      def send_data(data, _options = {})
        (@payloads ||= []) << data
      end
    end
  end
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = 'https://synthetic-public@example.invalid/931'
      config.environment = 'test'
      config.send_default_pii = true
      config.send_modules = false
      config.send_client_reports = false
      config.background_worker_threads = 0
      config.traces_sample_rate = 1.0
      config.logger = Logger.new(logs)
      config.transport.transport_class = transport_class
    end
  end
  let(:client) { Sentry::Client.new(configuration) }
  let(:hub) { Sentry::Hub.new(client, Sentry::Scope.new) }
  let(:transaction) { Sentry::Transaction.new(hub: hub, name: 'Instagram OAuth', op: 'http.server', sampled: true) }
  let(:http) do
    Class.new(Net::HTTP) do
      include Sentry::Net::HTTP
    end.new('graph.instagram.com', 443, nil)
  end
  let(:request_info) do
    http.use_ssl = true
    http.send(:extract_request_info, Net::HTTP::Get.new(URI.parse(url)))
  end
  let(:span) do
    transaction.start_child(op: 'http.client').tap do |child|
      http.send(:set_span_info, child, request_info, 200)
      child.finish
    end
  end
  let(:breadcrumbs) do
    Sentry::BreadcrumbBuffer.new.tap do |buffer|
      allow(Sentry).to receive(:add_breadcrumb) { |crumb| buffer.record(crumb) }
      body = URI.encode_www_form(secrets.merge(grant_type: 'authorization_code', jazoest: 'synthetic-checksum'))
      http.send(:record_sentry_breadcrumb, request_info.merge(body: body), 200)
    end
  end

  before do
    allow(Sentry).to receive(:configuration).and_return(configuration)
    allow(Sentry).to receive(:init).and_raise('Real SDK initialization is forbidden in these offline specs')
  end

  it 'reproduces the raw query in the installed SDK before sanitization, without HTTP or Sentry initialization' do
    expect(Sentry).not_to receive(:init)
    expect(http).not_to receive(:request)
    expect(span.data['http.query']).to include(secrets[:access_token], secrets[:client_secret])
    expect(breadcrumbs.peek.data[:query]).to eq(query)
    expect(client.transport.payloads).to be_nil
  end

  %i[event transaction].each do |kind|
    it "exports a sanitized SDK #{kind} envelope while retaining HTTP diagnostics" do
      # Build fixtures with the locked SDK's instrumentation and event constructors.
      span
      Sentry::Span.instance_method(:finish).bind_call(transaction)
      event = if kind == :transaction
                Sentry::TransactionEvent.new(transaction: transaction, configuration: configuration)
              else
                Sentry::ErrorEvent.new(configuration: configuration, message: "GET #{url}")
              end
      event.breadcrumbs = breadcrumbs
      event.contexts[:trace] = span.get_trace_context.merge(data: span.data)
      event.extra = { nested_events: [{ spans: [span.to_hash.merge(description: "GET #{url}")] }] }
      event.rack_env = Rack::MockRequest.env_for(url, 'HTTP_AUTHORIZATION' => 'Bearer synthetic-header-931')
      event.request.url = url
      event.request.headers['Referer'] = url
      event.request.headers['Accept'] = 'application/json'
      event.request.headers['X-FB-LSD'] = secrets[:lsd]
      event.request.cookies = { 'session' => 'synthetic-cookie-931' }
      event.add_exception_interface(RuntimeError.new("HTTP failed GET #{url}"), mechanism: Sentry::Mechanism.new) if kind == :event
      callback_name = kind == :transaction ? :before_send_transaction : :before_send
      configuration.public_send("#{callback_name}=", lambda do |item, _hint|
        item.tags[:callback_ran] = true
        item.request.headers['Proxy-Authorization'] = 'synthetic-added-header-931'
        item
      end)

      described_class.install(configuration)
      client.send_event(event)
      payload = client.transport.payloads.fetch(0)
      exported = JSON.parse(payload.lines.fetch(2))

      expect(secrets.values + %w[synthetic-header-931 synthetic-cookie-931 synthetic-added-header-931])
        .to all(satisfy { |secret| payload.exclude?(secret) })
      expect(exported.dig('extra', 'nested_events', 0, 'spans', 0, 'description')).to include('GET https://graph.instagram.com/access_token?')
      expect(URI.decode_www_form(exported.dig('contexts', 'trace', 'data', 'http.query')).to_h)
        .to include('access_token' => '[FILTERED]', 'fields' => 'id,username', 'grant_type' => 'ig_exchange_token')
      expect(exported.dig('breadcrumbs', 'values', 0, 'data')).to include('method' => 'GET', 'status' => 200)
      expect(exported.dig('request', 'headers')).to include('Accept' => 'application/json', 'Authorization' => '[FILTERED]')
      expect(exported.fetch('spans', [exported.dig('contexts', 'trace')]))
        .to contain_exactly(include('trace_id' => span.trace_id, 'span_id' => span.span_id))
      expect(exported.dig('tags', 'callback_ran')).to be(true)
    end

    it "removes URL userinfo from the serialized #{kind}, including additions by callbacks" do
      credential_url = 'https://synthetic-user-931:synthetic-pass-931@example.invalid/me'
      clean_url = 'https://example.invalid/me'
      span.set_description("GET #{credential_url}")
      span.set_data('url', credential_url)
      Sentry::Span.instance_method(:finish).bind_call(transaction)
      event = if kind == :transaction
                Sentry::TransactionEvent.new(transaction: transaction, configuration: configuration)
              else
                Sentry::ErrorEvent.new(configuration: configuration)
              end
      event.rack_env = Rack::MockRequest.env_for(clean_url)
      event.request.url = "#{credential_url}?#{query}"
      event.extra[:nested_spans] = [span.to_hash]
      event.breadcrumbs = Sentry::BreadcrumbBuffer.new
      event.breadcrumbs.record(Sentry::Breadcrumb.new(category: 'net.http', message: "GET #{credential_url}", data: { url: credential_url }))
      if kind == :event
        event.add_exception_interface(RuntimeError.new("HTTP failed GET #{credential_url}"), mechanism: Sentry::Mechanism.new)
        expect(event.exception.values).to be_an(Array)
      end
      callback_name = kind == :transaction ? :before_send_transaction : :before_send
      configuration.public_send("#{callback_name}=", lambda do |item, _hint|
        item.extra[:callback_url] = credential_url
        item.message = "Callback GET #{credential_url}"
        item
      end)
      described_class.install(configuration)
      client.send_event(event)
      payload = client.transport.payloads.fetch(0)
      exported = JSON.parse(payload.lines.fetch(2))

      expect(secrets.values + %w[synthetic-user-931 synthetic-pass-931]).to all(satisfy { |secret| payload.exclude?(secret) })
      expect(exported.dig('request', 'url')).to start_with("#{clean_url}?")
      expect(exported.dig('extra', 'callback_url')).to eq(clean_url)
      expect([exported['message'], exported.dig('breadcrumbs', 'values', 0, 'message')]).to eq(["Callback GET #{clean_url}", "GET #{clean_url}"])
      expect(exported.dig('extra', 'nested_spans', 0, 'description')).to eq("GET #{clean_url}")
      expect(exported.dig('exception', 'values')).to contain_exactly(include('value' => start_with("HTTP failed GET #{clean_url}"))) if kind == :event
    end
  end

  it 'covers string keys, repeated and encoded query keys, relative URLs, fragments, and nested HTTP headers' do
    repeated_query = URI.encode_www_form(
      [
        ['fields', 'id,username'],
        ['access_token', secrets[:access_token]],
        ['access_token', secrets[:client_secret]]
      ]
    )
    event = {
      'type' => 'transaction', 'event_id' => 'synthetic-931',
      'spans' => [{ 'description' => "POST #{url}", 'data' => {
        'http.query' => repeated_query.sub('access_token=', '%61ccess_token='),
        'url' => "/oauth/callback?code=#{secrets[:code]}&page=2#state=#{secrets[:state]}&tab=inbox",
        'headers' => { 'Proxy-Authorization' => 'synthetic-proxy-931', 'X-Api-Key' => 'synthetic-jjj', 'Accept' => 'application/json' },
        'http.request.header.authorization' => 'synthetic-bearer-931'
      } }],
      'breadcrumbs' => { 'values' => [{ 'data' => { 'query' => { 'access_token' => secrets[:access_token], 'fields' => 'id' } } }] }
    }
    described_class.install(configuration)
    client.send_event(event)
    payload = client.transport.payloads.fetch(0)
    exported = JSON.parse(payload.lines.fetch(2))

    expect(secrets.values + %w[synthetic-proxy-931 synthetic-jjj synthetic-bearer-931]).to all(satisfy { |secret| payload.exclude?(secret) })
    expect(exported.dig('spans', 0, 'data', 'url')).to include('/oauth/callback?', 'page=2', 'tab=inbox')
    filtered_pairs = URI.decode_www_form(exported.dig('spans', 0, 'data', 'http.query'))
    expect(filtered_pairs.count { |key, value| key == 'access_token' && value == '[FILTERED]' }).to eq(2)
    expect(exported.dig('breadcrumbs', 'values', 0, 'data', 'query')).to eq('access_token' => '[FILTERED]', 'fields' => 'id')
    expect(exported.dig('spans', 0, 'data', 'headers', 'Accept')).to eq('application/json')
  end

  it 'sanitizes SDK Span objects added by an existing callback before serialization' do
    span
    Sentry::Span.instance_method(:finish).bind_call(transaction)
    event = Sentry::TransactionEvent.new(transaction: transaction, configuration: configuration)
    configuration.before_send_transaction = lambda do |item, _hint|
      span.set_description("GET #{url}")
      span.set_data('http.query', query)
      span.set_tag(:Authorization, 'synthetic-span-header-931')
      item.spans = [span]
      item
    end
    described_class.install(configuration)
    client.send_event(event)
    payload = client.transport.payloads.fetch(0)
    exported = JSON.parse(payload.lines.fetch(2))

    expect(event.spans).to eq([span])
    expect(secrets.values + ['synthetic-span-header-931']).to all(satisfy { |secret| payload.exclude?(secret) })
    expect(exported.dig('spans', 0, 'data')).to include(
      Sentry::Span::DataConventions::HTTP_METHOD => 'GET', Sentry::Span::DataConventions::HTTP_STATUS_CODE => 200
    )
    expect(exported['spans']).to contain_exactly(include('span_id' => span.span_id))
  end

  it 'leaves non-sensitive queries and diagnostic values unchanged' do
    data = { :url => 'https://example.invalid/me?fields=id%2Cusername&page=2', 'http.query' => 'fields=id%2Cusername&page=2',
             :description => 'GET https://example.invalid/me?fields=id%2Cusername&page=2', :status => 200, :duration => 0.1,
             :message => "OAuth failure\n  with diagnostics", :body => 'fields=id%2Cusername&page=2', :headers => { Accept: 'application/json' },
             :tags => { code: 402, state: 'retryable' } }

    expect(described_class.scrub(data)).to eq(data)
  end

  it 'filters JSON HTTP bodies without losing non-sensitive fields' do
    data = { body: " \n#{JSON.generate(secrets.merge(grant_type: 'authorization_code'))}" }
    filtered = JSON.parse(described_class.scrub(data)[:body])

    expect(filtered).to include('client_secret' => '[FILTERED]', 'code' => '[FILTERED]', 'grant_type' => 'authorization_code')
    expect(filtered.values).not_to include(*secrets.values)
  end

  %i[before_send before_send_transaction].each do |callback_name|
    it "preserves #{callback_name} behavior and sanitizes its returned event" do
      hint = { background: false }
      calls = []
      callback = lambda do |event, callback_hint|
        calls << [event, callback_hint]
        { url: url, tags: { callback_ran: true } }
      end
      configuration.public_send("#{callback_name}=", callback)
      described_class.install(configuration)

      result = configuration.public_send(callback_name).call({ url: url }, hint)

      expect(result).to eq(url: described_class.scrub_url(url), tags: { callback_ran: true })
      expect(calls).to eq([[{ url: described_class.scrub_url(url) }, hint]])
    end

    it "preserves deliberate drops by #{callback_name}" do
      configuration.public_send("#{callback_name}=", ->(_event, _hint) {})
      described_class.install(configuration)

      expect(configuration.public_send(callback_name).call({ url: url }, {})).to be_nil
    end

    it "does not forward raw exceptions or payloads if #{callback_name} fails" do
      configuration.public_send("#{callback_name}=", ->(_event, _hint) { raise ArgumentError, url })
      described_class.install(configuration)
      event = { 'type' => callback_name == :before_send ? 'event' : 'transaction', 'url' => url }

      expect { client.send_event(event) }.not_to raise_error
      expect(client.transport.payloads).to be_nil
      expect(logs.string).not_to include(*secrets.values)
    end
  end

  it 'replaces malformed URL/query fields without forwarding raw parser errors' do
    data = { :url => "https://bad host.invalid/?#{query}", 'http.query' => "access_token=#{secrets[:access_token]}\xFF".b,
             :description => "GET https://bad[host]/?#{query}" }
    result = described_class.scrub(data)

    expect(result).to include(:url => '[FILTERED]', 'http.query' => '[FILTERED]')
    expect(JSON.generate(result)).not_to include(*secrets.values)
  end

  it 'installs both callbacks through the real initializer without initializing the SDK' do
    stub_const('Rails', Class.new)
    Rails.define_singleton_method(:root) { Pathname.new(File.expand_path('../..', __dir__)) }
    allow(Sentry).to receive(:init).and_yield(configuration)

    with_modified_env('SENTRY_DSN' => 'https://synthetic-public@example.invalid/931') do
      load File.expand_path('../../config/initializers/sentry.rb', __dir__)
    end

    expect(configuration.before_send.call({ url: url }, {})).to eq(url: described_class.scrub_url(url))
    expect(configuration.before_send_transaction.call({ url: url }, {})).to eq(url: described_class.scrub_url(url))
    expect(configuration.send_default_pii).to be(true)
    expect(configuration.excluded_exceptions).to include('Rack::Timeout::RequestTimeoutException', 'MutexApplicationJob::LockAcquisitionError')
  end
end
