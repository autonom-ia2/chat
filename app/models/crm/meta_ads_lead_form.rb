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

  # Os que a reconciliação relê (#2285): destino num funil ativo, na Página que a conta está recebendo, com os dois
  # marcos de início (destination_set_at e leadgen_receiving_since). Marco nulo fica de fora: sem saber desde quando,
  # não relê nada. As linhas de antes do #2285 ganharam o momento do deploy do #2740 como marco.
  scope :reconcilable, lambda {
    receiving = Crm::MetaAdsPage.leadgen_receiving.where.not(leadgen_receiving_since: nil)
                                .where('crm_meta_ads_pages.account_id = crm_meta_ads_lead_forms.account_id')
                                .where('crm_meta_ads_pages.page_id = crm_meta_ads_lead_forms.page_id')
    joins(:pipeline).merge(Crm::Pipeline.active).where.not(stage_id: nil).where.not(destination_set_at: nil)
                    .where(receiving.arel.exists)
  }

  # Funil reativado (#2804, item 4 da #2740): com ele arquivado o webhook não trouxe ninguém. Reativar vale como salvar o
  # destino naquela hora, e o marco nasce de novo, como em next_destination_set_at: a reconciliação não relê quem
  # preencheu com o funil fechado. Só nos formulários com destino completo; só o marco, sem callbacks nem updated_at.
  # Custo aceito: a janela é uma só, desde o marco. O que a última rodada antes de arquivar não pegou (menos de 1 hora)
  # e os leads recusados antes de arquivar não são relidos; para esses, o "trazer quem já preencheu".
  def self.restart_marks!(pipeline_id)
    where(pipeline_id: pipeline_id).where.not(stage_id: nil)
                                   .update_all(destination_set_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def destination?
    pipeline_id.present? && stage_id.present?
  end

  # O marco ao salvar um destino (#2285). Nasce quando o formulário passa a ter destino (ou ainda não tinha marco);
  # trocar de funil mantém o marco, porque o formulário já mandava gente para algum lugar. Destino num funil arquivado
  # não mandava ninguém (o webhook ignora): aí o marco nasce de novo. Chamar antes de gravar o destino novo: lê o anterior.
  def next_destination_set_at
    destination? && pipeline&.active? && destination_set_at ? destination_set_at : Time.current
  end
end
