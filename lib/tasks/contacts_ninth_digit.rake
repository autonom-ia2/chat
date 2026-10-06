namespace :contacts do
  # #990: merge contacts saved twice in one account, with and without the Brazilian ninth digit.
  # Dry-run by default: prints what would be merged. APPLY=1 writes. Ids and counts only in the output.
  #   ACCOUNT_ID=1 bundle exec rails contacts:merge_ninth_digit_duplicates
  #   ACCOUNT_ID=1 APPLY=1 bundle exec rails contacts:merge_ninth_digit_duplicates
  desc 'Merge contacts duplicated by the Brazilian ninth digit (keeps the one with the ninth digit)'
  task merge_ninth_digit_duplicates: :environment do
    account = Account.find(Integer(ENV.fetch('ACCOUNT_ID'), 10))
    apply = ENV['APPLY'] == '1'
    results = Contacts::NinthDigitDuplicateMerger.new(account: account, apply: apply).perform

    puts "contacts:merge_ninth_digit_duplicates account=#{account.id} (#{apply ? 'APPLY' : 'DRY-RUN'})"
    results.each { |result| puts "  #{result.to_line}" }
    results.map { |result| result.outcome.split(':').first }.tally.sort.each { |outcome, count| puts "  total #{outcome}: #{count}" }
    puts "  pairs found: #{results.size}"
    puts '  nothing was written; run again with APPLY=1 to merge' unless apply
    abort 'some pairs failed to merge; see the lines marked failed' if results.any? { |result| result.outcome.start_with?('failed') }
  end
end
