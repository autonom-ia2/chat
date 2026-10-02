class Waha::ExistingInboxMigrationPlanner
  Context = Struct.new(:channel, :inbox, :session, :app_id, keyword_init: true)
  Snapshot = Struct.new(:chatwoot, :session_info, :apps, :phone_app, keyword_init: true)
  Plan = Struct.new(:context, :snapshot, :desired_apps, :phone_app_id, :changes, keyword_init: true)
  SkipError = Class.new(StandardError)

  WORKING_STATUS = 'WORKING'.freeze

  def initialize(client:, config: Waha::Config)
    @client = client
    @config = config
  end

  def build(channel)
    context = migration_context(channel)
    raise SkipError, 'missing inbox/session/app_id' unless context

    validate_local_context!(context)
    snapshot = remote_snapshot(context)
    validate_remote_target!(context, snapshot.chatwoot)
    validate_preconditions!(context, snapshot)

    phone_app_id = snapshot.phone_app&.dig('id') || "br_#{SecureRandom.hex(16)}"
    desired_chatwoot = desired_chatwoot_app(snapshot.chatwoot)
    desired_phone = desired_phone_numbers_app(snapshot.phone_app, context.session, phone_app_id)

    Plan.new(
      context: context,
      snapshot: snapshot,
      desired_apps: desired_session_apps(snapshot, context, desired_chatwoot, desired_phone),
      phone_app_id: phone_app_id,
      changes: required_changes(context, snapshot, desired_chatwoot, desired_phone, phone_app_id)
    )
  end

  private

  def migration_context(channel)
    inbox = channel.inbox
    attrs = channel.additional_attributes.to_h
    session = attrs['session'].to_s
    app_id = attrs['app_id'].to_s
    return if inbox.blank? || session.blank? || app_id.blank?

    Context.new(channel: channel, inbox: inbox, session: session, app_id: app_id)
  end

  def remote_snapshot(context)
    chatwoot = @client.get_app(context.app_id)
    raise SkipError, 'remote app/session mismatch' unless remote_matches?(chatwoot, context)

    session_info = @client.get_session(context.session)
    raise SkipError, 'session config unavailable' unless session_info['config'].is_a?(Hash)

    apps = @client.list_apps(context.session)
    validate_chatwoot_snapshot!(apps, context, chatwoot)

    Snapshot.new(
      chatwoot: chatwoot,
      session_info: session_info.deep_dup,
      apps: apps.deep_dup,
      phone_app: find_phone_numbers_app(apps)&.deep_dup
    )
  end

  def validate_local_context!(context)
    raise SkipError, 'local_account_mismatch' unless context.channel.account_id == context.inbox.account_id
    raise SkipError, 'local_channel_mismatch' unless context.inbox.channel_type == 'Channel::Api' && context.inbox.channel_id == context.channel.id
  end

  def validate_remote_target!(context, chatwoot)
    expected = expected_remote_target(context)
    raise SkipError, 'chatwoot_base_url_missing' if expected['url'].blank?

    mismatches = remote_target_mismatches(chatwoot['config'].to_h, expected)
    return if mismatches.empty?

    raise SkipError, "remote_target_mismatch:#{mismatches.join(',')}"
  end

  def expected_remote_target(context)
    {
      'url' => normalized_url(@config.chatwoot_base_url),
      'accountId' => context.channel.account_id.to_s,
      'inboxId' => context.inbox.id.to_s,
      'inboxIdentifier' => context.channel.identifier.to_s
    }
  end

  def remote_target_mismatches(actual, expected)
    expected.filter_map do |key, expected_value|
      key unless remote_target_value_matches?(key, actual[key], expected_value)
    end
  end

  def remote_target_value_matches?(key, actual_value, expected_value)
    return normalized_url(actual_value) == expected_value if key == 'url'

    actual_value.to_s == expected_value
  end

  def normalized_url(value)
    value.to_s.strip.chomp('/')
  end

  def validate_preconditions!(context, snapshot)
    status = snapshot.session_info['status']
    raise SkipError, "session_not_working:#{status}" unless status == WORKING_STATUS
    return if @client.brazilian_phone_numbers_available?(context.session)

    raise SkipError, 'brazilian_phone_numbers_unavailable'
  end

  def remote_matches?(remote, context)
    remote['app'] == 'chatwoot' && remote['session'].to_s == context.session
  end

  def validate_chatwoot_snapshot!(remote_apps, context, chatwoot)
    listed_chatwoot = remote_apps.find { |app| app['id'] == context.app_id && app['app'] == 'chatwoot' }
    raise SkipError, 'chatwoot app absent from session app list' unless listed_chatwoot
    return if listed_chatwoot == chatwoot

    raise SkipError, 'O App Chatwoot mudou entre as leituras do planejamento. Nenhuma alteração foi aplicada.'
  end

  def find_phone_numbers_app(remote_apps)
    remote_apps.find { |app| app['app'] == Waha::BrazilianPhoneNumbers::APP_NAME }
  end

  def desired_chatwoot_app(remote)
    app = remote.deep_dup
    config = app['config'].to_h
    conversations = config['conversations'].to_h.merge(
      'outgoing' => 'message',
      'syncMessageStatus' => true,
      'sort' => Waha::Config.conversation_sort,
      'status' => nil
    )
    app['config'] = config.merge('conversations' => conversations)
    app
  end

  def desired_phone_numbers_app(phone_app, session, app_id)
    return Waha::BrazilianPhoneNumbers.desired_app(phone_app) if phone_app

    Waha::BrazilianPhoneNumbers.app_payload(session: session, app_id: app_id).deep_stringify_keys
  end

  def required_changes(context, snapshot, desired_chatwoot, desired_phone, phone_app_id)
    changes = []
    changes << 'remote_chatwoot_app' if desired_chatwoot != snapshot.chatwoot
    changes << 'brazilian_phone_numbers_app' if snapshot.phone_app.blank? || desired_phone != snapshot.phone_app
    changes << 'phone_numbers_app_reference' if stored_phone_app_id(context) != phone_app_id
    changes << 'single_conversation' unless context.inbox.lock_to_single_conversation?
    changes
  end

  def stored_phone_app_id(context)
    context.channel.additional_attributes.to_h['phone_numbers_app_id']
  end

  def desired_session_apps(snapshot, context, desired_chatwoot, desired_phone)
    apps = snapshot.apps.map do |app|
      next desired_chatwoot if app['id'] == context.app_id
      next desired_phone if snapshot.phone_app && app['id'] == snapshot.phone_app['id']

      app
    end
    apps << desired_phone unless snapshot.phone_app
    apps
  end
end
