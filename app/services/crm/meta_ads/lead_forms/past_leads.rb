# Quem preencheu um formulário nos últimos 90 dias (#2195): quantos são, para a tela, e trazer para o funil escolhido.
# Lê com o token da Página (leads_retrieval), tirado na hora do token do cliente e nunca guardado.
#
# As duas leituras rodam em segundo plano (CountPastJob e ImportPastJob), página a página até o fim: a tela só lê o
# número que ficou guardado, e um formulário com milhares de leads não segura a resposta nem gasta o limite de uso a
# cada abertura. A Meta não documenta contagem resumida no /{form}/leads, então contar é paginar.
class Crm::MetaAds::LeadForms::PastLeads
  WINDOW = 90.days
  COUNT_TTL = 15.minutes
  COUNTING_TTL = 5.minutes

  # Monta a leitura com o token da Página tirado da conexão da conta. nil quando a conta não tem conexão com token
  # próprio. Recusa da Meta sobe como Error; queda, como Unavailable.
  def self.for(account:, page_id:, form_id:, form_name:)
    connection = Crm::MetaAdsConnection.active.find_by(account_id: account.id)
    return unless connection&.own_token?

    result = Meta::AdsGraphClient.new(access_token: connection.read_token).page_access_token(page_id)
    check!(result)
    token = result.data.to_h['access_token']
    raise Crm::MetaAds::LeadForms::Error, 'meta_refused' if token.blank?

    new(account: account, page: { 'id' => page_id.to_s, 'access_token' => token }, form: { 'id' => form_id.to_s, 'name' => form_name })
  end

  def self.check!(result)
    return if result.ok
    raise Crm::MetaAds::LeadForms::Unavailable if result.transient?

    raise Crm::MetaAds::LeadForms::Error, 'meta_refused'
  end

  # O número que ficou guardado; sem ele, pede a contagem em segundo plano (uma por vez) e a tela mostra sem número.
  def self.cached_count(account:, page_id:, form_id:)
    key = cache_key(account.id, form_id)
    count = Rails.cache.read(key)
    return count unless count.nil?

    if Rails.cache.write([*key, 'counting'], true, expires_in: COUNTING_TTL, unless_exist: true)
      Crm::MetaAds::LeadForms::CountPastJob.perform_later(account.id, page_id.to_s, form_id.to_s)
    end
    nil
  end

  def self.cache_key(account_id, form_id)
    ['crm_meta_ads_lead_forms', 'past_count', account_id, form_id.to_s]
  end

  def initialize(account:, page:, form:)
    @account = account
    @page = page
    @form = form
  end

  def count!
    total, truncated = read
    Rails.cache.write(self.class.cache_key(@account.id, @form['id']), total.size, expires_in: COUNT_TTL)
    { count: total.size, truncated: truncated }
  end

  # Quantos viraram card novo (os repetidos e quem já tinha card aberto no funil não contam).
  def import!(pipeline:, stage:)
    questions = client.lead_form_questions(@form['id'])
    importer = Crm::MetaAds::LeadForms::Importer.new(
      account: @account, pipeline: pipeline, stage: stage, form_name: @form['name'], page_id: @page['id'],
      questions: questions.ok ? Array(questions.data.to_h['questions']) : []
    )
    rows, truncated = read
    imported = rows.count { |lead| importer.import(lead) == :created }
    Rails.cache.delete(self.class.cache_key(@account.id, @form['id']))
    { imported: imported, truncated: truncated }
  end

  private

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @page['access_token'])
  end

  def read
    list = []
    result, truncated = client.each_form_lead(@form['id'], since: WINDOW.ago) { |batch| list.concat(batch) }
    self.class.check!(result)
    [list.select { |lead| lead.is_a?(Hash) && lead['id'].present? }, truncated]
  end
end
