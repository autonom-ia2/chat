class Instagram::Automation::AccountRollout
  FEATURE = 'instagram_assisted_onboarding'.freeze
  MARKER = 'instagram_assisted_onboarding_rollout'.freeze

  def call(dry_run: true, confirmation: nil)
    raise ArgumentError, "Confirmation must equal #{FEATURE}" if !dry_run && confirmation != FEATURE

    counts = { would_enable: 0, enabled: 0, already_enabled: 0, processed: 0, ineligible: 0 }
    Account.find_each do |account|
      outcome = if dry_run
                  process_account(account, dry_run: true)
                else
                  account.with_lock { process_account(account, dry_run: false) }
                end
      counts[outcome] += 1
    end
    counts
  end

  private

  def process_account(account, dry_run:)
    # The channel flag is the account entitlement, not the presence of an inbox.
    return :ineligible unless account.feature_enabled?('channel_instagram')
    return :processed if account.internal_attributes.key?(MARKER)

    enabled = account.feature_enabled?(FEATURE)
    return enabled ? :already_enabled : :would_enable if dry_run

    account.enable_features(FEATURE) unless enabled
    # Mark already-enabled accounts too, so a subsequent opt-out is preserved.
    account.internal_attributes[MARKER] = true
    account.save!
    enabled ? :already_enabled : :enabled
  end
end
