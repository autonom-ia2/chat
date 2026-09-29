# Fixed, bounded operations invoked via SSM. No shell, tokens or client data are printed.
require 'json'
require 'base64'
require 'zlib'
require 'uri'
require 'securerandom'

module RelationshipsReleaseOperations
  FLAGS = %w[relationships_navigation relationships_attributes relationships_company_media].freeze
  ACTIONS = %w[preflight enable verify disable].freeze

  class IsolatedQueue
    attr_reader :suppressed

    def initialize
      @suppressed = []
    end

    def enqueue(job)
      @suppressed << job.class.name
    end

    def enqueue_at(job, _time)
      enqueue(job)
    end
  end

  def self.eligible(account)
    {
      FLAGS[0] => account.active? && %w[crm custom_attributes companies].any? { |name| account.feature_enabled?(name) },
      FLAGS[1] => account.active? && account.feature_enabled?('custom_attributes'),
      FLAGS[2] => account.active? && account.feature_enabled?('companies')
    }
  end

  def self.snapshot
    Account.order(:id).map do |account|
      { id: account.id, active: account.active?, eligible: eligible(account),
        enabled: FLAGS.index_with { |flag| account.respond_to?("feature_#{flag}?") && account.feature_enabled?(flag) } }
    end
  end

  def self.assert!(condition, message)
    raise message unless condition
  end

  def self.smoke!
    previous_adapter = ActiveJob::Base.queue_adapter
    isolated_queue = IsolatedQueue.new
    ActiveJob::Base.queue_adapter = isolated_queue
    checks = SmokeCommand.new.run!
    { passed: checks, suppressed_qa_callbacks: isolated_queue.suppressed.tally }
  ensure
    ActiveJob::Base.queue_adapter = previous_adapter if previous_adapter
    Current.reset
  end

  def self.encode_report(report)
    payload = Base64.strict_encode64(Zlib.gzip(JSON.generate(report)))
    envelope = JSON.generate(encoding: 'gzip-base64', payload: payload)
    assert!(envelope.bytesize < 20_000, 'Report exceeds the SSM output safety limit')
    envelope
  end

  def self.validate_operation!(action, expected)
    assert!(ACTIONS.include?(action), 'Unknown operation')
    assert!(Rails.env.production? || (Rails.env.test? && ENV['RELATIONSHIPS_OP_LOCAL_TEST'] == 'true'), 'Unexpected environment')
    assert!(File.read('/app/.git_sha').strip == expected, 'Application commit mismatch') unless Rails.env.test?
    assert!(Account.count <= 500, 'Account scope exceeds reviewed limit')
  end

  def self.update_account!(account, action)
    unchanged = account.all_features.except(*FLAGS)
    eligible(account).each do |flag, allowed|
      next unless allowed || action == 'disable'

      account.public_send("feature_#{flag}=", action == 'enable')
    end
    account.save! if account.changed?
    assert!(account.reload.all_features.except(*FLAGS) == unchanged, 'Unrelated account flags changed')
  end

  def self.update_flags!(action)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '5s'")
      Account.active.order(:id).lock.each { |account| update_account!(account, action) }
    end
  end

  def self.verify_flags!(rows)
    enabled = rows.all? { |row| row[:eligible].all? { |flag, allowed| !allowed || row[:enabled][flag] } }
    assert!(enabled, 'Eligible feature remains disabled')
  end

  def self.perform_operation!(action, report)
    assert!(report[:feature_code_available], 'Required application code is absent')
    report[:transactional_smoke] = smoke! if %w[enable verify].include?(action)
    update_flags!(action) if %w[enable disable].include?(action)
    report[:accounts_after] = snapshot
    verify_flags!(report[:accounts_after]) if %w[enable verify].include?(action)
  end

  def self.run!
    action = ENV.fetch('RELATIONSHIPS_OP_ACTION')
    expected = ENV.fetch('RELATIONSHIPS_EXPECTED_SHA')
    validate_operation!(action, expected)
    available = FLAGS.all? { |name| Account.new.respond_to?("feature_#{name}?") }
    Rails.logger.level = Logger::ERROR
    before = snapshot
    report = { action: action, sha: expected, feature_code_available: available, accounts_before: before }
    # Prove the transport bound before any flag write, including both snapshots.
    encode_report(report.merge(accounts_after: before, transactional_smoke: { passed: Array.new(12, 'synthetic_smoke_check') }))
    perform_operation!(action, report) unless action == 'preflight'
    puts "RELATIONSHIPS_OPS_RESULT #{encode_report(report)}"
  end
end

class RelationshipsReleaseOperations::SmokeContext
  attr_reader :account, :config_path

  delegate :assert!, to: :RelationshipsReleaseOperations

  def initialize
    @marker = "release-760-#{SecureRandom.hex(6)}"
  end

  def setup!
    @account = Account.create!(name: @marker, locale: :pt_BR)
    @created_id = account.id
    account.enable_features('companies', 'custom_attributes', 'crm', *RelationshipsReleaseOperations::FLAGS)
    account.save!
    user = create_user!
    create_membership!(user)
    @headers = user.create_new_auth_token
    @session = ActionDispatch::Integration::Session.new(Rails.application)
    @session.host!(URI.parse(ENV.fetch('FRONTEND_URL')).host)
    @session.https!
    @config_path = "/api/v1/accounts/#{account.id}/relationships/configuration"
  end

  def create_user!
    user = User.new(name: 'Release QA', email: "#{@marker}@example.invalid", password: SecureRandom.base64(32))
    user.skip_confirmation!
    user.save!
    user
  end

  def create_membership!(user)
    now = Time.current
    attributes = { account_id: account.id, user_id: user.id, role: 1, availability: 1, created_at: now, updated_at: now }
    AccountUser.new(attributes).validate!
    # Validated synthetic membership inside the rollback transaction only. Saving would run
    # presence/agent lifecycle callbacks outside the database transaction (including Redis).
    AccountUser.insert_all!([attributes]) # rubocop:disable Rails/SkipsModelValidations
  end

  def request!(verb, path, payload = nil, status = 200)
    options = { headers: @headers }
    if payload
      options[:params] = payload
      options[:as] = :json
    end
    @session.public_send(verb, path, **options)
    response = @session.response
    assert!(response.status == status, "Smoke route #{verb} #{path.split('/').last}: HTTP #{response.status}, expected #{status}")
    JSON.parse(response.body)
  end

  def verify_rollback!
    assert!(@created_id && !Account.exists?(id: @created_id), 'Synthetic account was not rolled back')
    assert!(!User.exists?(email: "#{@marker}@example.invalid"), 'Synthetic user was not rolled back')
  end
end

class RelationshipsReleaseOperations::SmokeCommand
  delegate :assert!, to: :RelationshipsReleaseOperations
  delegate :account, :config_path, :request!, to: :@context

  def initialize
    @context = RelationshipsReleaseOperations::SmokeContext.new
    @checks = []
  end

  def run!
    # All API mutations share this connection and are rolled back. No real user is modified.
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '5s'")
      @context.setup!
      check_configuration!
      check_contact!
      check_company!
      check_media!
      check_selection!
      raise ActiveRecord::Rollback
    end
    @context.verify_rollback!
    @checks << 'synthetic_database_changes_rolled_back'
  end

  def check_configuration!
    state = request!(:get, config_path)
    assert!(state['can_manage'] == true, 'Synthetic admin management denied')
    @checks << 'authenticated_configuration_read'
    @definition = { attribute_display_name: 'Cargo QA', attribute_description: 'Campo sintético de validação de publicação',
                    attribute_key: 'release_cargo_qa', attribute_model: 'contact_attribute', attribute_display_type: 'text' }
    saved = request!(:patch, config_path,
                     { configuration: { revision: state.dig('configuration', 'revision'), definition: @definition,
                                        display_on: %w[contact_details contact_sidebar] } })
    assert!(saved.dig('definition', 'attribute_key') == 'release_cargo_qa', 'Definition key mismatch')
    @checks << 'create_definition_and_global_presentation'
  end

  def check_contact!
    response = request!(:post, "/api/v1/accounts/#{account.id}/contacts", { name: 'Contato QA sem telefone ou email' })
    contact_id = response.dig('payload', 'contact', 'id') || response.dig('payload', 'id') || response['id']
    @contact = account.contacts.find(contact_id)
    path = "/api/v1/accounts/#{account.id}/relationships/contact/#{@contact.id}/values"
    request!(:patch, path, { field: { key: 'release_cargo_qa', previous: nil, value: 'CEO QA' } })
    assert!(@contact.reload.custom_attributes['release_cargo_qa'] == 'CEO QA', 'Value did not persist')
    @checks << 'contact_value_write_and_reload'
    request!(:patch, path, { field: { key: 'release_cargo_qa', previous: nil, value: 'stale' } }, 409)
    @checks << 'stale_value_conflict'
  end

  def check_company!
    @company = Company.create!(account: account, name: 'Empresa QA', description: 'Sem domínio, contatos externos ou integrações')
    definition = @definition.merge(attribute_display_name: 'Segmento QA', attribute_key: 'release_segmento_qa', attribute_model: 'company_attribute')
    state = request!(:get, config_path)
    request!(:patch, config_path,
             { configuration: { revision: state.dig('configuration', 'revision'), definition: definition, display_on: ['company_details'] } })
    request!(:patch, "/api/v1/accounts/#{account.id}/relationships/company/#{@company.id}/values",
             { field: { key: 'release_segmento_qa', previous: nil, value: 'QA' } })
    assert!(@company.reload.custom_attributes['release_segmento_qa'] == 'QA', 'Company value did not persist')
    assert!(!@contact.reload.custom_attributes.key?('release_segmento_qa'), 'Company value leaked to contact')
    @checks << 'company_definition_value_and_entity_isolation'
  end

  def check_media!
    media = request!(:get, "/api/v1/accounts/#{account.id}/companies/#{@company.id}/media?q=qa")
    assert!(media['payload'] == [] && media.dig('meta', 'total').in?([0]), 'Synthetic media query is not isolated')
    @checks << 'authenticated_company_media_search'
  end

  def check_selection!
    state = request!(:get, config_path)
    configuration = { revision: state.dig('configuration', 'revision'), surfaces: { contact_sidebar: { mode: 'custom', ids: [] } } }
    request!(:patch, config_path, { configuration: configuration })
    state = request!(:get, config_path)
    assert!(state.dig('configuration', 'surfaces', 'contact_sidebar') == { 'mode' => 'custom', 'ids' => [] }, 'Empty selection changed to default')
    @checks << 'empty_selection_survives_reload'
    request!(:patch, config_path, { configuration: { revision: 0, surfaces: {} } }, 409)
    @checks << 'global_revision_conflict'
  end
end

RelationshipsReleaseOperations.run!
