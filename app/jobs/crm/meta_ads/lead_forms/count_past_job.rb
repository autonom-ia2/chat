# Conta quem preencheu o formulário nos últimos 90 dias (#2195) e guarda o número para a tela (PastLeads.cached_count).
# Falha da Meta: a tela continua sem o número. A trava sai no fim, dê certo ou não, e a próxima abertura pede de novo.
class Crm::MetaAds::LeadForms::CountPastJob < ApplicationJob
  queue_as :low

  def perform(account_id, page_id, form_id)
    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?(Crm::MetaAds::LeadForms::ImportPastJob::FEATURE)

    Crm::MetaAds::LeadForms::PastLeads.for(account: account, page_id: page_id, form_id: form_id, form_name: nil)&.count!
  rescue Crm::MetaAds::LeadForms::Error
    nil
  ensure
    Rails.cache.delete(Crm::MetaAds::LeadForms::PastLeads.counting_key(account_id, form_id))
  end
end
