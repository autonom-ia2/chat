namespace :waha do
  desc 'Backfill existing WAHA inboxes for Chatwoot sync and Brazilian number resolution. DRY_RUN by default.'
  task backfill_existing_inboxes: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch('APPLY', nil)) || false
    account_id = ENV['ACCOUNT_ID'].presence&.to_i
    inbox_id = ENV.fetch('INBOX_ID', nil)
    unless inbox_id.nil?
      inbox_id = Integer(inbox_id, 10, exception: false)
      abort('[waha][backfill_existing_inboxes] INBOX_ID deve ser um inteiro positivo. Nenhuma caixa foi processada.') unless inbox_id&.positive?
    end

    puts(
      "[waha][backfill_existing_inboxes] mode=#{apply ? 'APPLY' : 'DRY_RUN'} " \
      "account_id=#{account_id || 'ALL'} inbox_id=#{inbox_id || 'ALL'}"
    )

    result = Waha::ExistingInboxUpdater.new.perform(apply: apply, account_id: account_id, inbox_id: inbox_id)

    puts(
      "[waha][backfill_existing_inboxes][done] total=#{result.total} would_update=#{result.would_update} " \
      "updated=#{result.updated} unchanged=#{result.unchanged} skipped=#{result.skipped} failed=#{result.failed} " \
      "recovered=#{result.recovered} recovery_failed=#{result.recovery_failed} halted=#{result.halted}"
    )

    if !apply && result.would_update.positive?
      puts '[waha][backfill_existing_inboxes] DRY_RUN only. Re-run with APPLY=true after reviewing the report.'
    end

    incomplete = result.failed.positive? || result.recovery_failed.positive? || (apply && result.skipped.positive?)
    abort('[waha][backfill_existing_inboxes] incomplete migration detected') if incomplete
  end
end
