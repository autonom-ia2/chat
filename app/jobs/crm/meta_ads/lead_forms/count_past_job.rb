# Conta quem preencheu o formulário nos últimos 90 dias (#2195) e guarda o número para a tela (PastLeads.cached_count).
# Falha da Meta: a tela continua sem o número, e a próxima abertura pede de novo.
class Crm::MetaAds::LeadForms::CountPastJob < ApplicationJob
  queue_as :low

  def perform(account_id, page_id, form_id)
    account = Account.find_by(id: account_id)
    return if account.nil?

    Crm::MetaAds::LeadForms::PastLeads.for(account: account, page_id: page_id, form_id: form_id, form_name: nil)&.count!
  rescue Crm::MetaAds::LeadForms::Error
    nil
  end
end
