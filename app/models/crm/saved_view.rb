# == Schema Information
#
# Table name: crm_saved_views
#
#  id          :bigint           not null, primary key
#  config      :jsonb            not null
#  name        :string           not null
#  position    :integer          default(0), not null
#  visibility  :integer          default("private_view"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  pipeline_id :bigint
#  user_id     :bigint           not null
#
# Indexes
#
#  idx_crm_saved_views_account_pipeline    (account_id,pipeline_id)
#  idx_crm_saved_views_account_user        (account_id,user_id)
#  idx_crm_saved_views_account_visibility  (account_id,visibility)
#  index_crm_saved_views_on_account_id     (account_id)
#  index_crm_saved_views_on_pipeline_id    (pipeline_id)
#  index_crm_saved_views_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#  fk_rails_...  (user_id => users.id)
#
class Crm::SavedView < ApplicationRecord
  self.table_name = 'crm_saved_views'

  belongs_to :account
  belongs_to :user
  belongs_to :pipeline, class_name: 'Crm::Pipeline', optional: true

  # private_view: visible only to its owner; team: shared with the owner's team;
  # account: shared with the whole account. (`private` is a Ruby keyword, hence
  # the `private_view` member name — the serialized value stays `private_view`.)
  enum visibility: { private_view: 0, team: 1, account: 2 }

  validates :name, presence: true
  validates :config, presence: true
  validates :config, jsonb_attributes_length: true
  validate :pipeline_belongs_to_same_account

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  # Views any user in the account may read: every non-private view plus the
  # caller's own private views.
  scope :visible_to, lambda { |user_id|
    where(visibility: [visibilities[:team], visibilities[:account]])
      .or(where(visibility: visibilities[:private_view], user_id: user_id))
  }

  def owned_by?(other_user)
    other_user.present? && user_id == other_user.id
  end

  private

  # Mirror the same-account invariant the rest of the CRM enforces, so a view
  # cannot reference a pipeline from another account.
  def pipeline_belongs_to_same_account
    return if pipeline.blank?
    return if pipeline.account_id == account_id

    errors.add(:pipeline, 'must belong to the same account')
  end
end
