# GlobalConfig caches InstallationConfig values in $alfred (MockRedis in test) for a day.
# InstallationConfig#after_commit clears that cache on write, but specs write inside the
# transactional fixture: the callback fires, the very next read re-caches the still
# uncommitted value, and the rollback then leaves the cache stale for the rest of the
# process. A spec that sets DEPLOYMENT_ENV=cloud (message_reports, enterprise accounts,
# fetch_imap_email_inboxes...) silently turns ChatwootApp.chatwoot_cloud? on for every
# later spec in the same worker (validate_token_api_access -> 403,
# ensure_portal_feature_enabled -> 402), which only shows up as order-dependent failures.
RSpec.configure do |config|
  config.after { GlobalConfig.clear_cache }
end
