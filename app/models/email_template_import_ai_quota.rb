# == Schema Information
#
# Table name: email_template_import_ai_quotas
#
#  id         :bigint           not null, primary key
#  period     :date             not null
#  used       :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_email_import_ai_quotas_on_account_and_period  (account_id,period) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#

# How many parts of imported models the AI rebuilt for an account in one month (#1099, delivery D). Written only by
# EmailCampaigns::Import::PartRebuild::Quota, with single conditional statements, so two clicks at the same time can
# never pass the ceiling.
class EmailTemplateImportAiQuota < ApplicationRecord
  self.table_name = 'email_template_import_ai_quotas'

  belongs_to :account
end
