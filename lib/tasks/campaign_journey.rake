namespace :campaign_journey do
  # Públicos (#1005, F1). Dry-run by default: prints what would be linked. APPLY=1 writes.
  #   bundle exec rails campaign_journey:backfill_audience_links
  #   APPLY=1 bundle exec rails campaign_journey:backfill_audience_links
  desc 'Link old WhatsApp campaigns to the old campaign imports they used (through the base label)'
  task backfill_audience_links: :environment do
    apply = ENV['APPLY'] == '1'
    counts = CampaignJourney::AudienceLinkBackfill.new(apply: apply).perform
    puts "campaign_journey:backfill_audience_links (#{apply ? 'APPLY' : 'DRY-RUN'})"
    counts.each { |name, count| puts "  #{name}: #{count}" }
    puts '  nothing was written; run again with APPLY=1 to create the links' unless apply
  end
end
