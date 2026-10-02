class Waha::ExistingInboxUpdater
  Result = Struct.new(:total, :would_update, :updated, :unchanged, :skipped, :failed, keyword_init: true)

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
    context = migration_context(channel)
    return skip(channel, result, 'missing inbox/session/app_id') unless context

    remote = @client.get_app(context[:app_id])
    return skip(channel, result, 'remote app/session mismatch') unless remote_matches?(remote, context)

    desired = desired_app(remote)
    changes = required_changes(remote, desired, context[:inbox])
    return unchanged(channel, result) if changes.empty?

    result.would_update += 1
    return dry_run(channel, changes) unless apply

    apply_changes(context, desired, changes)
    result.updated += 1
    log(channel, 'UPDATED', changes.join(','))
  rescue StandardError => e
    failed(channel, result, e)
  end

  def migration_context(channel)
    inbox = channel.inbox
    attrs = channel.additional_attributes.to_h
    session = attrs['session'].to_s
    app_id = attrs['app_id'].to_s
    return if inbox.blank? || session.blank? || app_id.blank?

    { inbox: inbox, session: session, app_id: app_id }
  end

  def remote_matches?(remote, context)
    remote['app'] == 'chatwoot' && remote['session'].to_s == context[:session]
  end

  def desired_app(remote)
    app = remote.deep_dup
    config = app['config'].to_h
    conversations = config['conversations'].to_h.merge(
      'outgoing' => 'message',
      'syncMessageStatus' => true
    )
    app['config'] = config.merge('conversations' => conversations)
    app
  end

  def required_changes(remote, desired, inbox)
    changes = []
    changes << 'remote_chatwoot_app' if desired != remote
    changes << 'single_conversation' unless inbox.lock_to_single_conversation?
    changes
  end

  def apply_changes(context, desired, changes)
    @client.update_app(context[:app_id], desired) if changes.include?('remote_chatwoot_app')
    context[:inbox].update!(lock_to_single_conversation: true) if changes.include?('single_conversation')
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
