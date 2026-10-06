namespace :contacts do
  # #990: merge contacts saved twice in one account, with and without the Brazilian ninth digit.
  # Dry-run by default: prints what would be merged. APPLY=1 writes. Ids, counts and flags only in the output.
  # In production it runs only through .github/workflows/ops-contacts-merge-ninth-digit.yml
  # (runbook: docs/runbooks/ops-contacts-merge-ninth-digit.md).
  #   ACCOUNT_ID=1 bundle exec rails contacts:merge_ninth_digit_duplicates
  #   ACCOUNT_ID=1 APPLY=1 bundle exec rails contacts:merge_ninth_digit_duplicates
  desc 'Merge contacts duplicated by the Brazilian ninth digit (keeps the one with the ninth digit)'
  task merge_ninth_digit_duplicates: :environment do
    # Contact data must not reach the logs: no job arguments, no SQL with bind values, no info lines.
    ActiveJob::Base.log_arguments = false
    [Rails.logger, ActiveRecord::Base.logger].compact.uniq.each { |logger| logger.level = :warn }
    $stdout.sync = true

    account = Account.find(Integer(ENV.fetch('ACCOUNT_ID'), 10))
    apply = ENV['APPLY'] == '1'
    puts "contacts:merge_ninth_digit_duplicates account=#{account.id} (#{apply ? 'APPLY' : 'DRY-RUN'})"

    results = Contacts::NinthDigitDuplicateMerger.new(account: account, apply: apply).perform { |result| puts "  #{result.to_line}" }

    totals = results.map { |result| result.outcome.split(':').first }.tally.sort.map { |outcome, count| "#{outcome}=#{count}" }
    puts "  totals: pairs=#{results.size} #{totals.join(' ')}".rstrip
    puts '  nothing was written; run again with APPLY=1 to merge' unless apply
    abort 'some pairs failed to merge; see the lines marked failed' if results.any? { |result| result.outcome.start_with?('failed') }
  end
end
