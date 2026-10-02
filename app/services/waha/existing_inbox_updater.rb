class Waha::ExistingInboxUpdater
  Result = Struct.new(:total, :would_update, :updated, :unchanged, :skipped, :failed, keyword_init: true)
  Context = Struct.new(:channel, :inbox, :session, :app_id, keyword_init: true)
  Snapshot = Struct.new(:chatwoot, :session_info, :apps, :phone_app, keyword_init: true)
  Plan = Struct.new(:context, :snapshot, :desired_apps, :phone_app_id, :changes, keyword_init: true)
  SkipError = Class.new(StandardError)

  REMOTE_CHANGES = %w[remote_chatwoot_app brazilian_phone_numbers_app].freeze

  def initialize(client: Waha::Client.new, output: $stdout)
    @client = client
    @output = output
  end

  def perform(apply: false, account_id: nil)
    result = empty_result

    scope(account_id).find_each do |channel|
      result.total += 1
      process_channel(channel, apply, result)
    end

    result
  end

  private

  def empty_result
    Result.new(total: 0, would_update: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0)
  end

  def scope(account_id)
    relation = Channel::Api.includes(:inbox)
                           .where("channel_api.additional_attributes ->> 'provider' = ?", 'waha')
    account_id.present? ? relation.where(account_id: account_id) : relation
  end

  def process_channel(channel, apply, result)
    plan = build_plan(channel)
    return unchanged(channel, result) if plan.changes.empty?

    result.would_update += 1
    return dry_run(channel, plan.changes) unless apply

    apply_plan(plan)
    result.updated += 1
    log(channel, 'UPDATED', plan.changes.join(','))
  rescue SkipError => e
    skip(channel, result, e.message)
  rescue StandardError => e
    failed(channel, result, e)
  end

  def build_plan(channel)
    context = migration_context(channel)
    raise SkipError, 'missing inbox/session/app_id' unless context

    snapshot = remote_snapshot(context)
    phone_app_id = snapshot.phone_app&.dig('id') || "br_#{SecureRandom.hex(16)}"
    desired_chatwoot = desired_chatwoot_app(snapshot.chatwoot)
    desired_phone = desired_phone_numbers_app(snapshot.phone_app, context.session, phone_app_id)
    changes = required_changes(context, snapshot, desired_chatwoot, desired_phone, phone_app_id)
    desired_apps = desired_session_apps(snapshot, context, desired_chatwoot, desired_phone)

    Plan.new(context: context, snapshot: snapshot, desired_apps: desired_apps, phone_app_id: phone_app_id, changes: changes)
  end

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
      session_info: session_info,
      apps: apps,
      phone_app: find_phone_numbers_app(apps)
    )
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

  def apply_plan(plan)
    if plan.changes.intersect?(REMOTE_CHANGES)
      @client.update_session(
        plan.context.session,
        config: plan.snapshot.session_info['config'],
        apps: plan.desired_apps
      )
    end
    persist_local_changes(plan)
  end

  def persist_local_changes(plan)
    if plan.changes.include?('phone_numbers_app_reference')
      attrs = plan.context.channel.additional_attributes.to_h.merge('phone_numbers_app_id' => plan.phone_app_id)
      plan.context.channel.update!(additional_attributes: attrs)
    end
    plan.context.inbox.update!(lock_to_single_conversation: true) if plan.changes.include?('single_conversation')
  end

  def skip(channel, result, detail)
    result.skipped += 1
    log(channel, 'SKIP', detail)
  end

  def unchanged(channel, result)
    result.unchanged += 1
    log(channel, 'OK', 'already compliant')
  end

  def dry_run(channel, changes)
    log(channel, 'DRY_RUN', changes.join(','))
  end

  def failed(channel, result, error)
    result.failed += 1
    Rails.logger.error("[Waha] existing inbox backfill failed channel=#{channel.id}: #{error.class}")
    log(channel, 'FAILED', error.class.name)
  end

  def log(channel, status, detail)
    @output.puts(
      "[waha][existing_inbox] #{status} account=#{channel.account_id} channel=#{channel.id} " \
      "inbox=#{channel.inbox&.id || '-'} #{detail}"
    )
  end
end
