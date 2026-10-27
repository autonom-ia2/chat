# Traz para o funil quem preencheu o formulário nos últimos 90 dias (#2195), em segundo plano: "Trazer também quem já
# preencheu" ao escolher o destino, e "Trazer" de formulário arquivado (brought). Lê até o fim; o Importer não duplica,
# então rodar de novo é seguro. O resultado fica na Auditoria da conta, com quantos entraram e se a leitura parou no
# teto (truncated).
class Crm::MetaAds::LeadForms::ImportPastJob < ApplicationJob
  queue_as :low
  retry_on Crm::MetaAds::LeadForms::Unavailable, wait: :polynomially_longer, attempts: 5

  # rubocop:disable Metrics/ParameterLists
  def perform(account_id, page_id, form_id, pipeline_id, stage_id, user_id: nil, brought: false)
    account = Account.find_by(id: account_id)
    record = account && Crm::MetaAdsLeadForm.find_by(account_id: account.id, form_id: form_id.to_s)
    stage = record && active_stage(account, pipeline_id, stage_id)
    return if stage.nil?

    result = import(account, record, page_id, stage.pipeline, stage)
    Crm::MetaAdsLeadForm.update_counters(record.id, brought_count: result[:imported].to_i) if brought # rubocop:disable Rails/SkipsModelValidations
    audit!(account, user_id, form_id, result.merge(brought: brought))
  end
  # rubocop:enable Metrics/ParameterLists

  private

  # O funil pode ter sido arquivado, ou a etapa apagada, entre o clique e o job: aí não traz ninguém.
  def active_stage(account, pipeline_id, stage_id)
    account.crm_pipelines.active.find_by(id: pipeline_id)&.stages&.find_by(id: stage_id)
  end

  def import(account, record, page_id, pipeline, stage)
    past = Crm::MetaAds::LeadForms::PastLeads.for(account: account, page_id: page_id, form_id: record.form_id, form_name: record.form_name)
    return { import_error: 'not_connected' } if past.nil?

    past.import!(pipeline: pipeline, stage: stage)
  rescue Crm::MetaAds::LeadForms::Unavailable
    raise
  rescue Crm::MetaAds::LeadForms::Error => e
    { import_error: e.code }
  end

  def audit!(account, user_id, form_id, result)
    Audited.audit_class.create!(auditable: account, user: User.find_by(id: user_id), action: 'meta_ads_lead_form_past_imported',
                                audited_changes: { 'form_id' => form_id.to_s }.merge(result.stringify_keys).compact)
  end
end
