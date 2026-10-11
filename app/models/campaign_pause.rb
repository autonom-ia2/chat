# == Schema Information
#
# Table name: campaign_pauses
#
#  id            :bigint           not null, primary key
#  details       :jsonb            not null
#  pausable_type :string           not null
#  paused_at     :datetime         not null
#  reason_code   :string           not null
#  resumed_at    :datetime
#  source        :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  pausable_id   :bigint           not null
#  paused_by_id  :bigint
#  resumed_by_id :bigint
#
# Indexes
#
#  idx_campaign_pauses_on_pausable          (pausable_type,pausable_id,paused_at)
#  idx_campaign_pauses_one_open             (pausable_type,pausable_id) UNIQUE WHERE (resumed_at IS NULL)
#  index_campaign_pauses_on_account_id      (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (paused_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (resumed_by_id => users.id) ON DELETE => nullify
#
# Why a campaign is paused (#1329, épico #1320): one generic record for every campaign engine,
# so the reason is never lost again (e-mail campaign #32 was paused on 15/09 with nothing saved).
# Open while resumed_at is NULL; at most one open pause per campaign (partial unique index).
# - source: who decided — template (the WhatsApp template no longer matches), email_protection,
#   manual (a person) or system (the platform could not check something).
# - reason_code: a stable code the screens translate; details: technical facts, never personal data.
# The template check is the first writer (CampaignPauses::WhatsappDispatchGate); e-mail comes later.
class CampaignPause < ApplicationRecord
  PAUSABLE_TYPES = %w[Campaign EmailCampaign].freeze

  belongs_to :account
  belongs_to :pausable, polymorphic: true
  belongs_to :paused_by, class_name: 'User', optional: true
  belongs_to :resumed_by, class_name: 'User', optional: true

  enum :source, { template: 'template', email_protection: 'email_protection', manual: 'manual', system: 'system' }, prefix: true

  validates :pausable_type, inclusion: { in: PAUSABLE_TYPES }
  validates :reason_code, presence: true
  validates :paused_at, presence: true
  validate :same_account

  scope :in_effect, -> { where(resumed_at: nil) }

  def self.open_for(pausable)
    in_effect.find_by(pausable_type: pausable.class.name, pausable_id: pausable.id)
  end

  def open?
    resumed_at.nil?
  end

  # What the result screens show (no personal data is ever stored in details).
  def payload
    {
      id: id, source: source, reason_code: reason_code, details: details, paused_at: paused_at,
      paused_by_id: paused_by_id, resumed_at: resumed_at, resumed_by_id: resumed_by_id
    }
  end

  private

  def same_account
    errors.add(:pausable, 'must belong to the same account') if pausable && pausable.account_id != account_id
  end
end
