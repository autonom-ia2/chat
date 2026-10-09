# == Schema Information
#
# Table name: crm_pipelines
#
#  id            :bigint           not null, primary key
#  counts_as_sale :boolean          default(TRUE), not null
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

  before_validation :initialize_followup_days, on: :create
  before_save :turn_off_conversion_sync, unless: :counts_as_sale?

  validates :name, presence: true
  validates :metadata, jsonb_attributes_length: true

  private

  # Funil que não conta como venda (#1144) não manda nada para Meta nem Google, nem mudança de etapa: a sincronização
  # é desligada ao salvar, para não virar conversão de anúncio por engano.
  def turn_off_conversion_sync
    config = (metadata || {}).deep_dup
    %w[meta_sync google_sync].each do |key|
      config[key] = config[key].merge('enabled' => false) if config[key].is_a?(Hash)
    end
    self.metadata = config
  end

  def initialize_followup_days
    config = (metadata || {}).deep_dup
    config['ai'] = {
      'enabled' => true, 'auto_move_enabled' => true, 'attribute_extraction_enabled' => true,
      'score_enabled' => true, 'callback_enabled' => true, 'stale_hours' => Crm::Ai::Config::DEFAULT_STALE_HOURS
    }.merge(config['ai'] || {})
    config['ai']['auto_followup'] ||= {}
    config['ai']['auto_followup']['allowed_days'] ||= [1, 2, 3, 4, 5]
    self.metadata = config
  end
end
