# A single aggregate read of the account scope, independent of search and pagination.
class Relationships::Summary
  PERIOD = 30.days
  CONTACT_METRICS = {
    new_in_period: 'created_at >= :cutoff',
    active_in_period: 'last_activity_at >= :cutoff',
    with_company: 'company_id IS NOT NULL'
  }.freeze
  COMPANY_METRICS = {
    new_in_period: 'created_at >= :cutoff',
    with_contacts: 'contacts_count > 0',
    inactive_in_period: 'last_activity_at < :cutoff OR (last_activity_at IS NULL AND created_at < :cutoff)'
  }.freeze

  def self.contacts(account)
    scope = account.contacts.resolved_contacts(use_crm_v2: account.feature_enabled?('crm_v2'))
    call(scope, CONTACT_METRICS)
  end

  def self.call(scope, metrics)
    cutoff = Time.current - PERIOD
    columns = ['COUNT(*)'] + metrics.values.map do |condition|
      sql = scope.model.sanitize_sql_array([condition, { cutoff: cutoff }])
      "COUNT(*) FILTER (WHERE #{sql})"
    end
    values = scope.pick(*columns.map { |sql| Arel.sql(sql) })
    (%i[total] + metrics.keys).zip(values).to_h
  end
end
