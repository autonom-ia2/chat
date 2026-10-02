class Waha::ExistingInboxMigrationExecutor
  Outcome = Struct.new(:status, :error_class, :reason, keyword_init: true)
  VerificationError = Class.new(StandardError)

  REMOTE_CHANGES = %w[remote_chatwoot_app brazilian_phone_numbers_app].freeze
  WORKING_STATUS = 'WORKING'.freeze

  def initialize(client:, sleeper:, health_attempts:, health_interval:)
    @client = client
    @sleeper = sleeper
    @health_attempts = health_attempts
    @health_interval = health_interval
  end

  def perform(plan)
    remote_write_attempted = false

    begin
      unless remote_snapshot_current?(plan)
        return Outcome.new(
          status: :skipped,
          reason: 'A configuração remota mudou após o planejamento. Nenhuma alteração foi aplicada; lote interrompido.'
        )
      end

      if plan.changes.intersect?(REMOTE_CHANGES)
        remote_write_attempted = true
        update_remote(plan)
      end
      persist_local_changes(plan)
      Outcome.new(status: :updated)
    rescue StandardError => e
      return recover_after_failed_write(plan, e) if remote_write_attempted

      Outcome.new(status: :failed, error_class: e.class.name)
    end
  end

  private

  def remote_snapshot_current?(plan)
    current_session = @client.get_session(plan.context.session)
    current_apps = @client.list_apps(plan.context.session)

    current_session['status'] == plan.snapshot.session_info['status'] &&
      current_session['config'] == plan.snapshot.session_info['config'] &&
      current_apps.sort_by { |app| app['id'].to_s } == plan.snapshot.apps.sort_by { |app| app['id'].to_s }
  end

  def update_remote(plan)
    @client.update_session(
      plan.context.session,
      config: plan.snapshot.session_info['config'],
      apps: plan.desired_apps
    )
    wait_for_working!(plan.context.session)
    verify_remote_state!(plan)
  end

  def verify_remote_state!(plan)
    current_session = @client.get_session(plan.context.session)
    current_apps = @client.list_apps(plan.context.session)
    return if current_session['config'] == plan.snapshot.session_info['config'] &&
              stable_apps(current_apps) == stable_apps(plan.desired_apps)

    raise VerificationError, 'desired_remote_state_not_confirmed'
  end

  def persist_local_changes(plan)
    ActiveRecord::Base.transaction do
      persist_phone_app_reference(plan)
      plan.context.inbox.update!(lock_to_single_conversation: true) if plan.changes.include?('single_conversation')
    end
  end

  def persist_phone_app_reference(plan)
    return unless plan.changes.include?('phone_numbers_app_reference')

    attrs = plan.context.channel.additional_attributes.to_h.merge('phone_numbers_app_id' => plan.phone_app_id)
    plan.context.channel.update!(additional_attributes: attrs)
  end

  def recover_after_failed_write(plan, error)
    return Outcome.new(status: :recovered, error_class: error.class.name) if recover_remote_snapshot(plan)

    Outcome.new(status: :recovery_failed, error_class: error.class.name)
  end

  def recover_remote_snapshot(plan)
    @client.update_session(
      plan.context.session,
      config: plan.snapshot.session_info['config'],
      apps: plan.snapshot.apps
    )
    ensure_initial_health!(plan)
    snapshot_restored?(plan)
  rescue StandardError
    false
  end

  def ensure_initial_health!(plan)
    return unless plan.snapshot.session_info['status'] == WORKING_STATUS

    current = @client.get_session(plan.context.session)
    @client.start_session(plan.context.session) unless current['status'] == WORKING_STATUS
    wait_for_working!(plan.context.session)
  end

  def snapshot_restored?(plan)
    current_session = @client.get_session(plan.context.session)
    current_apps = @client.list_apps(plan.context.session)

    current_session['status'] == WORKING_STATUS &&
      current_session['config'] == plan.snapshot.session_info['config'] &&
      stable_apps(current_apps) == stable_apps(plan.snapshot.apps)
  end

  def wait_for_working!(session)
    working = false

    @health_attempts.times do |attempt|
      working = @client.get_session(session)['status'] == WORKING_STATUS
      break if working

      @sleeper.call(@health_interval) if attempt < @health_attempts - 1
    end

    raise VerificationError, 'session_did_not_return_to_working' unless working
  end

  def stable_apps(apps)
    projection = apps.map do |app|
      {
        'id' => app['id'],
        'session' => app['session'],
        'app' => app['app'],
        'enabled' => app['enabled'],
        'config' => app['config']
      }
    end
    projection.sort_by { |app| app['id'].to_s }
  end
end
