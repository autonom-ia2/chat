# Anúncios da Meta › Formulários (#2195): as Páginas que a pessoa concedeu ao entrar com o Facebook, os formulários
# instantâneos de cada uma e para onde vai quem preenche. O token da Página vem de me/accounts, na hora, com o token do
# cliente; nunca é guardado, logado nem devolvido à tela.
#
# - Escolher o funil de um formulário liga o recebimento da Página (assina o leadgen nela, pages_manage_metadata) e,
#   se pedido, traz quem preencheu nos últimos 90 dias (leads_retrieval).
# - Parar tira só o leadgen da Página; os destinos ficam guardados para voltar.
# - Formulário arquivado não recebe ninguém novo: só traz quem já preencheu, sem destino e sem ligar a Página.
#
# Só no modo em que o token é do próprio cliente (Crm::MetaAdsConnection#own_token?): no `partner` o token é o da
# plataforma, e me/accounts traria Páginas de outros clientes.
class Crm::MetaAds::LeadForms::Hub
  LEADGEN = 'leadgen'.freeze
  ACTIVE = 'ACTIVE'.freeze
  SHOWN_STATUSES = %w[ACTIVE ARCHIVED].freeze
  PAST_WINDOW = 90.days
  # Quantos preencheram nos últimos 90 dias: lido da Meta uma vez a cada 15 minutos por formulário, para a tela não
  # gastar o limite de uso a cada abertura.
  PAST_COUNT_TTL = 15.minutes

  def initialize(connection:, account:)
    @connection = connection
    @account = account
  end

  # visible_cards: os cards que a pessoa enxerga (nil quando ela não vê a lista de quem chegou).
  def payload(pipelines:, visible_cards:)
    recent = Crm::MetaAds::LeadForms::RecentLeads.new(@account, visible_cards: visible_cards).payload if visible_cards
    { pages: pages.map { |page| page_payload(page) }, pipelines: pipelines, recent_leads: recent }
  end

  def receive!(page_id)
    page = find_page!(page_id)
    subscription(page).add!([LEADGEN])
    page_record(page).update!(leadgen_receiving: true)
  rescue Crm::MetaAds::PageSubscription::Error => e
    raise_meta(e)
  end

  # A mesma Página pode estar em outra conta que ainda recebe: aí só esta conta para, e a assinatura fica.
  def stop!(page_id)
    page = find_page!(page_id)
    subscription(page).remove!([LEADGEN]) unless receiving_elsewhere?(page)
    page_record(page).update!(leadgen_receiving: false)
  rescue Crm::MetaAds::PageSubscription::Error => e
    raise_meta(e)
  end

  # A Página já está ligada e o destino guardado quando os antigos são lidos: se a Meta recusar essa leitura, o destino
  # vale mesmo assim (imported: 0 e import_error), em vez de a tela dizer que falhou com a Página já recebendo.
  def save_destination!(form_id, pipeline:, stage:, import_past:)
    page, form = find_form!(form_id)
    raise Crm::MetaAds::LeadForms::Error, 'form_archived' unless form['status'] == ACTIVE

    receive!(page['id'])
    record = form_record(page, form)
    record.update!(pipeline: pipeline, stage: stage)
    result = { destination: destination_payload(record), imported: 0 }
    import_past ? result.merge(past_result(page, form, pipeline, stage)) : result
  end

  def bring_past!(form_id, pipeline:, stage:)
    page, form = find_form!(form_id)
    raise Crm::MetaAds::LeadForms::Error, 'form_active' if form['status'] == ACTIVE

    imported = import_past!(page, form, pipeline, stage)
    record = form_record(page, form)
    record.update!(brought_count: record.brought_count.to_i + imported, brought_pipeline: pipeline, brought_stage: stage)
    { imported: imported, pipeline_name: pipeline.name, stage_name: stage.name }
  end

  def remove_destination!(form_id)
    record = Crm::MetaAdsLeadForm.find_by(account_id: @account.id, form_id: form_id.to_s)
    raise Crm::MetaAds::LeadForms::Error, 'form_not_found' if record.nil?

    record.update!(pipeline: nil, stage: nil)
  end

  def page_name(page_id)
    pages.find { |page| page['id'] == page_id.to_s }&.dig('name')
  end

  private

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end

  def page_client(page)
    Meta::AdsGraphClient.new(access_token: page['access_token'])
  end

  def subscription(page)
    Crm::MetaAds::PageSubscription.new(page_id: page['id'], access_token: page['access_token'])
  end

  def receiving_elsewhere?(page)
    Crm::MetaAdsPage.leadgen_receiving.where(page_id: page['id']).where.not(account_id: @account.id).exists?
  end

  def past_result(page, form, pipeline, stage)
    { imported: import_past!(page, form, pipeline, stage) }
  rescue Crm::MetaAds::LeadForms::Error => e
    { import_error: e.code }
  end

  def raise_meta(error)
    raise Crm::MetaAds::LeadForms::Unavailable if error.transient?

    raise Crm::MetaAds::LeadForms::Error, 'meta_refused'
  end

  def pages
    @pages ||= begin
      list = @connection.own_token? ? Array(check!(client.pages_with_tokens).data.to_h['data']) : []
      list = list.select { |page| page.is_a?(Hash) && page['id'].present? && page['access_token'].present? }
                 .map { |page| page.merge('id' => page['id'].to_s) }
      Crm::MetaAdsPage.remember!(@account, list)
      list
    end
  end

  def find_page!(page_id)
    pages.find { |page| page['id'] == page_id.to_s } || raise(Crm::MetaAds::LeadForms::Error, 'page_not_found')
  end

  def find_form!(form_id)
    pages.each do |page|
      form = forms_of(page).find { |item| item['id'] == form_id.to_s }
      return [page, form] if form
    end
    raise Crm::MetaAds::LeadForms::Error, 'form_not_found'
  end

  def forms_of(page)
    @forms ||= {}
    @forms[page['id']] ||= Array(check!(page_client(page).leadgen_forms(page['id'])).data.to_h['data'])
                           .select { |form| form.is_a?(Hash) && SHOWN_STATUSES.include?(form['status']) }
                           .map { |form| form.merge('id' => form['id'].to_s) }
  end

  def check!(result)
    return result if result.ok
    raise Crm::MetaAds::LeadForms::Unavailable if result.transient?

    raise Crm::MetaAds::LeadForms::Error, 'meta_refused'
  end

  def page_record(page)
    Crm::MetaAdsPage.find_or_create_by!(account_id: @account.id, page_id: page['id']) { |record| record.name = page['name'] }
  end

  # Dois cliques ao mesmo tempo no mesmo formulário: o segundo acha a linha que o primeiro criou.
  def form_record(page, form)
    attempts ||= 0
    record = Crm::MetaAdsLeadForm.find_or_initialize_by(account_id: @account.id, form_id: form['id'])
    record.assign_attributes(page_id: page['id'], form_name: form['name'].to_s.first(Crm::MetaAdsLeadForm::NAME_LIMIT))
    record.save! if record.changed?
    record
  rescue ActiveRecord::RecordNotUnique
    (attempts += 1) < 2 ? retry : raise
  end

  def page_payload(page)
    records = Crm::MetaAdsLeadForm.where(account_id: @account.id, page_id: page['id'])
                                  .includes(:pipeline, :stage, :brought_pipeline, :brought_stage).index_by(&:form_id)
    receiving = Crm::MetaAdsPage.exists?(account_id: @account.id, page_id: page['id'], leadgen_receiving: true)
    {
      id: page['id'], name: page['name'], receiving: receiving,
      forms: forms_of(page).map { |form| form_payload(page, form, records[form['id']]) }
    }
  end

  def form_payload(page, form, record)
    destination = record&.destination? ? destination_payload(record) : nil
    brought = brought_payload(record)
    {
      id: form['id'], name: form['name'], status: form['status'], leads_count: form['leads_count'].to_i,
      last_lead_at: last_lead_at(form['id']), destination: destination, brought: brought,
      past_count: destination || brought ? 0 : past_count(page, form)
    }
  end

  def destination_payload(record)
    { pipeline_id: record.pipeline_id, pipeline_name: record.pipeline&.name, stage_id: record.stage_id, stage_name: record.stage&.name }
  end

  def brought_payload(record)
    return if record&.brought_count.blank?

    { count: record.brought_count, pipeline_name: record.brought_pipeline&.name, stage_name: record.brought_stage&.name }
  end

  def last_lead_at(form_id)
    @last_leads ||= Crm::MetaAdsLead.where(account_id: @account.id).group(:form_id).maximum(:received_at)
    @last_leads[form_id]&.iso8601
  end

  # Falha da Meta ao contar não derruba a tela: o formulário aparece sem o número (nil), e o resto segue.
  def past_count(page, form)
    Rails.cache.fetch(past_count_key(form), expires_in: PAST_COUNT_TTL) { past_leads(page, form).size }
  rescue Crm::MetaAds::LeadForms::Error
    nil
  end

  def past_count_key(form)
    ['crm_meta_ads_lead_forms', 'past_count', @account.id, form['id']]
  end

  def past_leads(page, form)
    @past ||= {}
    @past[form['id']] ||= begin
      rows = []
      result = page_client(page).each_form_lead(form['id'], since: PAST_WINDOW.ago) { |batch| rows.concat(batch) }
      check!(result)
      rows.select { |lead| lead.is_a?(Hash) && lead['id'].present? }
    end
  end

  def import_past!(page, form, pipeline, stage)
    questions = page_client(page).lead_form_questions(form['id'])
    importer = Crm::MetaAds::LeadForms::Importer.new(
      account: @account, pipeline: pipeline, stage: stage, form_name: form['name'], page_id: page['id'],
      questions: questions.ok ? Array(questions.data.to_h['questions']) : []
    )
    imported = past_leads(page, form).count { |lead| importer.import(lead) == :created }
    Rails.cache.delete(past_count_key(form))
    imported
  end
end
