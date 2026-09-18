class EmailCampaigns::Maintenance::Start
  def self.call(account:, actor:, parameters:, config: EmailCampaigns::Maintenance::Config.new)
    raise Pundit::NotAuthorizedError unless EmailProtectionMaintenancePolicy.authorized?(actor, account.id)

    attributes = EmailCampaigns::Maintenance::Request.new(parameters).attributes
    raise EmailCampaigns::Maintenance::Request::Invalid, 'apply_disabled' unless attributes[:dry_run] || config.apply_enabled?

    scope = EmailProtectionMaintenanceRun.where(account_id: account.id)
    run = scope.find_by(idempotency_key: attributes.fetch(:idempotency_key)) || create_run(scope, account, actor, attributes)
    # Rails' uniqueness validation can race before the unique constraint is hit.
    check_request!(run, attributes)
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.errors.of_kind?(:idempotency_key, :taken)

    check_request!(scope.find_by!(idempotency_key: attributes.fetch(:idempotency_key)), attributes)
  end

  def self.create_run(scope, account, actor, attributes)
    scope.create_or_find_by!(idempotency_key: attributes.fetch(:idempotency_key)) do |row|
      row.assign_attributes(attributes.merge(actor_id: actor.id, next_dispatch_at: Time.current,
                                             event_horizon: EmailCampaigns::Maintenance::Evidence.events(account.id).maximum('email_events.id') || 0,
                                             legacy_horizon: EmailSuppression.where(account_id: account.id).maximum(:id) || 0))
    end
  end

  def self.check_request!(run, attributes)
    raise EmailCampaigns::Maintenance::Request::Invalid, 'idempotency_conflict' unless attributes.all? { |key, value| run.public_send(key) == value }

    run.reload
  end
  private_class_method :create_run, :check_request!
end
