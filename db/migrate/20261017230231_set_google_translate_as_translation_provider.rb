# Fork (upgrade 4.19.1, #3119): without this, accounts with the Google Translate hook would fall back to the
# `captain` provider (Enterprise::Account#translation_provider) and lose the translation they have today. The write
# goes straight to `settings` (no validations or callbacks), so one account with legacy settings cannot abort the
# deploy halfway.
# rubocop:disable Rails/SkipsModelValidations -- data backfill: validations and callbacks must not run here.
class SetGoogleTranslateAsTranslationProvider < ActiveRecord::Migration[7.2]
  def up
    Account.where(id: Integrations::Hook.where(app_id: 'google_translate').select(:account_id)).find_each do |account|
      settings = account.settings || {}
      next if settings['translation_provider'].present?

      account.update_columns(settings: settings.merge('translation_provider' => 'google_translate'))
    end
  end

  def down
    Account.where("settings ->> 'translation_provider' = 'google_translate'").find_each do |account|
      account.update_columns(settings: account.settings.except('translation_provider'))
    end
  end
end
# rubocop:enable Rails/SkipsModelValidations
