# The monthly ceiling of "Refazer para editar" per account (#1099, delivery D): PER_MONTH parts, counted in UTC months.
# `take` adds one with a single INSERT ... ON CONFLICT DO UPDATE ... WHERE used < PER_MONTH, so the count is atomic —
# two clicks at the same time never pass the ceiling — and answers the month it counted in (nil when the ceiling was
# reached); `give_back` returns one to that month when the AI was never asked (it was not configured any more).
module EmailCampaigns::Import::PartRebuild::Quota
  PER_MONTH = 50

  module_function

  def take(account, now = Time.current)
    period = period_of(now)
    sql = <<~SQL.squish
      INSERT INTO email_template_import_ai_quotas (account_id, period, used, created_at, updated_at)
      VALUES (:account_id, :period, 1, :now, :now)
      ON CONFLICT (account_id, period)
      DO UPDATE SET used = email_template_import_ai_quotas.used + 1, updated_at = :now
      WHERE email_template_import_ai_quotas.used < :limit
      RETURNING used
    SQL
    taken = connection.exec_query(sanitize(sql, account_id: account.id, period: period, now: now, limit: PER_MONTH))
    taken.rows.any? ? period : nil
  end

  def give_back(account, period)
    EmailTemplateImportAiQuota.where(account_id: account.id, period: period).where('used > 0')
                              .update_all(['used = used - 1, updated_at = ?', Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end

  def left(account, now = Time.current)
    used = EmailTemplateImportAiQuota.where(account_id: account.id, period: period_of(now)).pick(:used).to_i
    [PER_MONTH - used, 0].max
  end

  def period_of(time)
    time.utc.to_date.beginning_of_month
  end

  def connection
    EmailTemplateImportAiQuota.connection
  end

  def sanitize(sql, values)
    EmailTemplateImportAiQuota.sanitize_sql_array([sql, values])
  end
end
