class Waha::ExistingInboxMigrationPlanner
  Context = Struct.new(:channel, :inbox, :session, :app_id, keyword_init: true)
  Snapshot = Struct.new(:chatwoot, :session_info, :apps, :phone_app, keyword_init: true)
  Plan = Struct.new(:context, :snapshot, :desired_apps, :phone_app_id, :changes, keyword_init: true)
  SkipError = Class.new(StandardError)

  WORKING_STATUS = 'WORKING'.freeze

  def initialize(client:)
    @client = client
  end

  def build(channel)
    context = migration_context(channel)
    raise SkipError, 'missing inbox/session/app_id' unless context

    snapshot = remote_snapshot(context)
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
    raise SkipError, 'chatwoot app absent from session app list' unless app_list_matches?(apps, context)

    Snapshot.new(
      chatwoot: chatwoot,
      session_info: session_info.deep_dup,
      apps: apps.deep_dup,
      phone_app: find_phone_numbers_app(apps)&.deep_dup
    )
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

  def app_list_matches?(remote_apps, context)
    remote_apps.any? { |app| app['id'] == context.app_id && app['app'] == 'chatwoot' }
  end

  def find_phone_numbers_app(remote_apps)
    remote_apps.find { |app| app['app'] == Waha::BrazilianPhoneNumbers::APP_NAME }
  end

  def desired_chatwoot_app(remote)
    app = remote.deep_dup
    config = app['config'].to_h
    conversations = config['conversations'].to_h.merge(
      'outgoing' => 'message',
      'syncMessageStatus' => true
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
