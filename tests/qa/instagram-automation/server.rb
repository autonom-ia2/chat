# frozen_string_literal: true

# Standalone, test-only Rack wrapper. Product controllers/services/routes are unchanged.
require 'json'
require 'securerandom'
require 'logger'

ROOT = File.expand_path('../../..', __dir__)
READY = File.join(ROOT, 'tmp/950-integration/browser-ready.json')
raise 'browser-ready.json required; coordinator owns the database window' unless File.file?(READY)
raise 'test environment required' unless ENV['RAILS_ENV'] == 'test' && ENV['RACK_ENV'] == 'test'
raise 'exclusive PostgreSQL required' unless ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_PORT'] == '59510'
raise 'exclusive Redis required' unless ENV['REDIS_URL'] == 'redis://127.0.0.1:59511/0'
raise 'local fixture capability required' if ENV.fetch('INSTAGRAM_QA_CAPABILITY', '').length < 32

require File.join(ROOT, 'config/boot')
require 'rails/all'
require 'dotenv'
require 'dotenv/rails'
# Also protects the explicit Dotenv::Rails.load in config/application.rb.
Dotenv::Rails.files = ['/dev/null']
ENV['VITE_RUBY_AUTO_BUILD'] = 'false'
ENV['CI'] = 'true' # ViteRuby serves the built manifest rather than probing another worktree's dev server.
# Ephemeral test encryption values, never production configuration or output.
%w[ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT].each do |key|
  ENV[key] = SecureRandom.hex(32)
end
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
require File.join(ROOT, 'config/environment')
require 'factory_bot'
require 'puma'

raise 'Rails test required' unless Rails.env.test?

db = ActiveRecord::Base.connection_db_config.configuration_hash
raise 'unexpected database connection' unless db[:host] == '127.0.0.1' && db[:port].to_i == 59_510 && db[:database] == 'chatwoot_test'
raise 'real build required in public/vite-test' unless File.file?(File.join(ROOT, 'public/vite-test/.vite/manifest.json'))

# Never log request bodies, credentials, headers or SQL fixture inserts.
Rails.logger = Logger.new(File::NULL)
ActiveRecord::Base.logger = Rails.logger
ActionController::Base.logger = Rails.logger
ActionController::Base.allow_forgery_protection = true
SuperAdmin::InstagramAutomationsController.allow_forgery_protection = true
ActionMailer::Base.delivery_method = :test
ActiveJob::Base.queue_adapter = :test
# factory_bot_rails already loads spec/factories during Rails initialization.
# Test initializer otherwise uses MockRedis. This private QA process exercises real CAS/TTL.
# rubocop:disable Style/GlobalVars -- Product Redis adapter uses this process-local pool; isolated QA only.
$alfred = ConnectionPool.new(size: 5, timeout: 1) do
  Redis::Namespace.new('alfred', redis: Redis.new(url: ENV.fetch('REDIS_URL'), timeout: 1, reconnect_attempts: 0))
end
# rubocop:enable Style/GlobalVars

ENV['INSTAGRAM_TESTER_SESSION_SOURCE'] = 'managed'
ENV['INSTAGRAM_TESTER_SESSION_NAMESPACE'] = "qa950-#{SecureRandom.hex(8)}"
ENV['INSTAGRAM_TESTER_PROXY_HOST'] = '192.0.2.10'
ENV['INSTAGRAM_TESTER_PROXY_PORT'] = '8080'
ENV['INSTAGRAM_TESTER_PROXY_AUTH_MODE'] = 'ip'
ENV['INSTAGRAM_TESTER_COORDINATION_REDIS_URL'] = ''
%w[INSTAGRAM_TESTER_PROXY_USERNAME INSTAGRAM_TESTER_PROXY_PASSWORD INSTAGRAM_TESTER_SESSION_JSON].each { |key| ENV.delete(key) }

class InstagramAutomationQA
  def initialize
    @password = "Aa9!#{SecureRandom.hex(24)}"
    run_id = SecureRandom.hex(8)
    @admin = FactoryBot.create(:super_admin, name: 'QA950 Synthetic SuperAdmin', email: "qa950-super-#{run_id}@example.invalid", password: @password)
    @account = FactoryBot.create(:account, name: "empresa_demo_qa950_#{run_id}", domain: 'example.invalid')
    @user = FactoryBot.create(:user, name: 'QA950 Synthetic AccountAdmin', display_name: 'empresa_demo',
                                     email: "qa950-user-#{run_id}@example.invalid", password: @password,
                                     account: @account, role: 'administrator')
    @channel = FactoryBot.create(:channel_instagram, account: @account, instagram_id: "950#{rand(10**10)}")
    @initial_channel = @channel.reload.attributes.slice('id', 'account_id', 'instagram_id', 'access_token', 'expires_at')
    @locale = :pt_BR
  end

  def call(env)
    return [403, {}, []] unless env['REMOTE_ADDR'] == '127.0.0.1'

    request = Rack::Request.new(env)
    return support_sdk if request.get? && request.path == '/packs/js/sdk.js'

    if request.path.start_with?('/__qa/')
      return [403, {}, []] unless env['HTTP_X_QA_CAPABILITY'] == ENV.fetch('INSTAGRAM_QA_CAPABILITY')

      return Rails.application.executor.wrap { fixture(request) }
    end
    I18n.with_locale(@locale) { Rails.application.call(env) }
  end

  private

  def fixture(request)
    data = request.post? ? JSON.parse(request.body.read) : {}
    case [request.request_method, request.path]
    when ['GET', '/__qa/bootstrap'] then bootstrap
    when ['GET', '/__qa/receipt'] then receipt
    when ['POST', '/__qa/state'] then operator_fixture(data.fetch('state'))
    when ['POST', '/__qa/locale']
      @locale = { 'pt_BR' => :pt_BR, 'en' => :en }.fetch(data.fetch('locale'))
      json(translations: I18n.t('super_admin.instagram_automation', locale: @locale))
    else json({ error: 'unknown_fixture_endpoint' }, 404)
    end
  end

  def bootstrap
    json(admin_email: @admin.email, admin_id: @admin.id, account_email: @user.email, password: @password, account_id: @account.id,
         namespace: ENV.fetch('INSTAGRAM_TESTER_SESSION_NAMESPACE'),
         translations: I18n.t('super_admin.instagram_automation', locale: @locale))
  end

  # Explicit support SDK dependency fixture; never a product or Meta endpoint.
  def support_sdk
    @support_sdk_requests = (@support_sdk_requests || 0) + 1
    script = <<~JS
      window.chatwootSDK = { run() {
        window.$chatwoot = { setUser() {} };
        window.__qaSupportSdkReady = true;
        window.dispatchEvent(new CustomEvent('chatwoot:ready'));
      }};
    JS
    [200, { 'content-type' => 'application/javascript', 'cache-control' => 'no-store' }, [script]]
  end

  # Test-only projection of independent real sources, without implementing their behavior.
  # rubocop:disable Metrics/AbcSize
  def receipt
    status = Instagram::Automation::LocalStatus.new.call
    # JSON.generate(Time) drops milliseconds; retain the rendered HTML's ISO3 precision.
    status[:checked_at] = status.fetch(:checked_at).utc.iso8601(3)
    json(metadata: Instagram::Automation::Metadata.new.values,
         status: status,
         account_enabled: @account.reload.feature_enabled?('instagram_assisted_onboarding'),
         channel_preserved: @channel.reload.attributes.slice(*@initial_channel.keys) == @initial_channel,
         inbox_preserved: Inbox.exists?(channel: @channel),
         support_sdk_simulated: true, support_sdk_requests: @support_sdk_requests || 0,
         smtp_deliveries: ActionMailer::Base.deliveries.length,
         jobs: ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job].name },
         remote_requests: WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |signature| URI(signature.uri).host }.uniq)
  end
  # rubocop:enable Metrics/AbcSize

  def operator_fixture(state)
    operator = Instagram::Automation::OperatorControl.new
    case state
    when 'unknown'
      key = "#{Instagram::Automation::OperatorControl::ROOT_KEY}:#{ENV.fetch('INSTAGRAM_TESTER_SESSION_NAMESPACE')}:manager"
      Redis::Alfred.delete(key) # Only this run's heartbeat; requests/sessions/outcomes remain.
    when 'operator_disconnected', 'operator_available', 'healthy' then heartbeat_fixture(operator, state)
    when 'running' then operator.claim(operator.status.fetch(:control).fetch('id'))
    when 'failed', 'operator_required' then operator.complete(operator.status.fetch(:control).fetch('id'), state)
    when 'succeeded' then publish_fixture(operator)
    else return json({ error: 'unknown_fixture_state' }, 422)
    end
    json(status: operator.status)
  end

  def heartbeat_fixture(operator, state)
    operator.heartbeat(state: state == 'healthy' ? 'healthy' : 'operator_required', control_available: state == 'operator_available')
  end

  # A fixed synthetic publication payload exercises the real publisher/store protocol.
  def publish_fixture(operator)
    publisher = Instagram::Automation::SessionPublisher.new
    snapshot = publisher.call('type' => 'session', 'operation' => 'bootstrap')
    metadata = snapshot.fetch(:metadata)
    admin_id = metadata.fetch('INSTAGRAM_TESTER_ADMIN_USER_ID')
    publisher.call(
      'type' => 'session', 'operation' => 'publish', 'request_id' => operator.status.fetch(:control).fetch('id'),
      'session' => { 'cookie' => "c_user=#{admin_id}; xs=qa950-synthetic", 'fb_dtsg' => 'qa950-synthetic',
                     'lsd' => 'qa950-synthetic', 'jazoest' => '9500', 'user_id' => admin_id, 'user_agent' => 'QA950 Synthetic' },
      'expected_version' => snapshot.fetch(:version), 'captured_at' => Time.current.utc.iso8601(6),
      'app_id' => metadata.fetch('INSTAGRAM_META_DEVELOPER_APP_ID'), 'business_id' => metadata.fetch('INSTAGRAM_META_BUSINESS_ID'),
      'proxy_fingerprint' => Instagram::Testers::Proxy.new.fingerprint,
      'roles_response' => { 'data' => { 'get_app_roles' => { 'app_roles' => [] } } }.to_json,
      'configuration_revision' => snapshot.fetch(:revision), 'roles_doc_id' => metadata.fetch('INSTAGRAM_TESTER_ROLES_DOC_ID')
    )
  end

  def json(value, status = 200)
    [status, { 'content-type' => 'application/json', 'cache-control' => 'no-store' }, [JSON.generate(value)]]
  end
end

server = Puma::Server.new(InstagramAutomationQA.new)
server.add_tcp_listener('127.0.0.1', 39_510)
%w[TERM INT].each { |signal| Signal.trap(signal) { server.stop } }
server.run.join
