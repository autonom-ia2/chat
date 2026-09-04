# == Schema Information
#
# Table name: crm_ai_stage_suggestions
#
#  id            :bigint           not null, primary key
#  confidence    :decimal(5, 4)    not null
#  metadata      :jsonb            not null
#  model_used    :string           not null
#  reasoning     :string(500)
#  status        :integer          default("pending"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  card_id       :bigint           not null
#  from_stage_id :bigint           not null
#  to_stage_id   :bigint           not null
#
# Indexes
#
#  idx_crm_ai_suggestions_account_status_created    (account_id,status,created_at)
#  idx_crm_ai_suggestions_card_status_created       (card_id,status,created_at)
#  index_crm_ai_stage_suggestions_on_account_id     (account_id)
#  index_crm_ai_stage_suggestions_on_card_id        (card_id)
#  index_crm_ai_stage_suggestions_on_from_stage_id  (from_stage_id)
#  index_crm_ai_stage_suggestions_on_to_stage_id    (to_stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (from_stage_id => crm_pipeline_stages.id)
#  fk_rails_...  (to_stage_id => crm_pipeline_stages.id)
#
class Crm::AiStageSuggestion < ApplicationRecord
  self.table_name = 'crm_ai_stage_suggestions'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :from_stage, class_name: 'Crm::PipelineStage'
  belongs_to :to_stage, class_name: 'Crm::PipelineStage'

  enum status: { pending: 0, accepted: 1, dismissed: 2, auto_applied: 3, expired: 4 }

  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :reasoning, length: { maximum: 500 }, allow_nil: true
  validates :model_used, presence: true
  validates :metadata, jsonb_attributes_length: true
  validate :stages_must_belong_to_account

  scope :current_pending, -> { where(status: :pending).order(created_at: :desc) }

  private

  def stages_must_belong_to_account
    return if account_id.blank?

    [from_stage, to_stage].compact.each do |stage|
      next if stage.account_id == account_id

      errors.add(:base, 'stages must belong to the same account')
      break
    end
  end
end
