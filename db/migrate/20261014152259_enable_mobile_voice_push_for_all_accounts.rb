# Upstream (#16254) turns mobile_voice_push on in the stored feature defaults and for every account.
# Fork (#3119, upgrade 4.19.1): kept as a no-op so the version stays in schema_migrations and no account changes.
# Voice is not used by the fork; the flag stays off (config/features.yml) until someone asks for it.
class EnableMobileVoicePushForAllAccounts < ActiveRecord::Migration[7.0]
  def up; end

  def down; end
end
