# == Schema Information
#
# Table name: crm_pipelines
#
#  id            :bigint           not null, primary key
#  description   :text
#  is_default    :boolean          default(FALSE), not null
#  metadata      :jsonb            not null
#  name          :string           not null
#  position      :integer          default(0), not null
#  status        :integer          default("active"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_crm_pipelines_on_account_id                 (account_id)
#  index_crm_pipelines_on_account_id_and_is_default  (account_id,is_default)
#  index_crm_pipelines_on_account_id_and_position    (account_id,position)
#  index_crm_pipelines_on_account_id_and_status      (account_id,status)
#  index_crm_pipelines_on_created_by_id              (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class Crm::Pipeline < ApplicationRecord
  self.table_name = 'crm_pipelines'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :stages, class_name: 'Crm::PipelineStage', dependent: :destroy
  has_many :pipeline_inboxes, class_name: 'Crm::PipelineInbox', dependent: :destroy
  has_many :inboxes, through: :pipeline_inboxes
  has_many :cards, class_name: 'Crm::Card', dependent: :restrict_with_error

  enum status: { active: 0, archived: 1 }

  validates :name, presence: true
  validates :metadata, jsonb_attributes_length: true
end
