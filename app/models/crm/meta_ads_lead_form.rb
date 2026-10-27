# Formulário instantâneo de um anúncio da Meta (#2195): para onde vai quem preenche (funil e etapa) e, do formulário
# arquivado, quantos dos últimos 90 dias já foram trazidos e para onde (brought_*).
class Crm::MetaAdsLeadForm < ApplicationRecord
  self.table_name = 'crm_meta_ads_lead_forms'

  NAME_LIMIT = 255

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :stage, class_name: 'Crm::PipelineStage', optional: true
  belongs_to :brought_pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :brought_stage, class_name: 'Crm::PipelineStage', optional: true

  validates :page_id, :form_id, presence: true
  validates :form_id, uniqueness: { scope: :account_id }

  def destination?
    pipeline_id.present? && stage_id.present?
  end
end
