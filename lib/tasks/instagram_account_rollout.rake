namespace :instagram do
  desc 'Roll out assisted onboarding to existing channel-eligible accounts (DRY_RUN=true by default; INSTAGRAM_ROLLOUT_CONFIRM required to apply)'
  task rollout_assisted_onboarding: :environment do
    mode = ENV.fetch('DRY_RUN', 'true')
    raise ArgumentError, 'DRY_RUN must be true or false' unless %w[true false].include?(mode)

    counts = Instagram::Automation::AccountRollout.new.call(
      dry_run: mode == 'true',
      confirmation: ENV.fetch('INSTAGRAM_ROLLOUT_CONFIRM', nil)
    )
    puts "[instagram:rollout_assisted_onboarding] dry_run=#{mode} #{counts.map { |key, value| "#{key}=#{value}" }.join(' ')}"
  end
end
