# Quem preencheu um formulário nos últimos 90 dias (#2195): quantos são, para a tela, e trazer para o funil escolhido.
# Lê com o token da Página (leads_retrieval), que vem de me/accounts na hora e não é guardado.
class Crm::MetaAds::LeadForms::PastLeads
  WINDOW = 90.days
  # Quantos preencheram: lido da Meta uma vez a cada 15 minutos por formulário, para a tela não gastar o limite de uso
  # a cada abertura.
  COUNT_TTL = 15.minutes

  def initialize(account:, page:, form:)
    @account = account
    @page = page
    @form = form
  end

  # Falha da Meta ao contar não derruba a tela: o formulário aparece sem o número (nil), e o resto segue.
  def count
    Rails.cache.fetch(cache_key, expires_in: COUNT_TTL) { rows.size }
  rescue Crm::MetaAds::LeadForms::Error
    nil
  end

  # Quantos viraram card novo (os repetidos e quem já tinha card aberto no funil não contam).
  def import!(pipeline:, stage:)
    questions = client.lead_form_questions(@form['id'])
    importer = Crm::MetaAds::LeadForms::Importer.new(
      account: @account, pipeline: pipeline, stage: stage, form_name: @form['name'], page_id: @page['id'],
      questions: questions.ok ? Array(questions.data.to_h['questions']) : []
    )
    imported = rows.count { |lead| importer.import(lead) == :created }
    Rails.cache.delete(cache_key)
    imported
  end

  private

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @page['access_token'])
  end

  def cache_key
    ['crm_meta_ads_lead_forms', 'past_count', @account.id, @form['id']]
  end

  def rows
    @rows ||= begin
      list = []
      result = client.each_form_lead(@form['id'], since: WINDOW.ago) { |batch| list.concat(batch) }
      check!(result)
      list.select { |lead| lead.is_a?(Hash) && lead['id'].present? }
    end
  end

  def check!(result)
    return if result.ok
    raise Crm::MetaAds::LeadForms::Unavailable if result.transient?

    raise Crm::MetaAds::LeadForms::Error, 'meta_refused'
  end
end
