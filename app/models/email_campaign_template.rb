# == Schema Information
#
# Table name: email_campaign_templates
#
#  id            :bigint           not null, primary key
#  body_html     :text
#  body_mjml     :text
#  category      :string
#  name          :string           not null
#  thumbnail_url :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint
#
# Indexes
#
#  index_email_campaign_templates_account_lower_name_unique  (account_id, lower((name)::text)) UNIQUE WHERE (account_id IS NOT NULL)
#  index_email_campaign_templates_global_lower_name_unique   (lower((name)::text)) UNIQUE WHERE (account_id IS NULL)
#  index_email_campaign_templates_on_account_id              (account_id)
#  index_email_campaign_templates_on_account_id_and_name     (account_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class EmailCampaignTemplate < ApplicationRecord
  # account is optional: account_id IS NULL marks a GLOBAL gallery template shared with every account.
  belongs_to :account, optional: true

  # Real compiled email HTML/MJML easily exceeds ApplicationRecord's global 20k text cap;
  # declare an explicit (generous) limit so the global guard skips these columns.
  BODY_MAX = 500_000

  validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :body_html, length: { maximum: BODY_MAX }
  validates :body_mjml, length: { maximum: BODY_MAX }

  scope :by_category, ->(category) { where(category: category) if category.present? }
  scope :global, -> { where(account_id: nil) }
  scope :for_account, ->(account) { where(account: account).or(global) }
end
