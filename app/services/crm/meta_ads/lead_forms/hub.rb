# Anúncios da Meta › Formulários (#2195): as Páginas que a pessoa concedeu ao entrar com o Facebook, os formulários
# instantâneos de cada uma e para onde vai quem preenche. O token da Página vem de me/accounts, na hora, com o token do
# cliente; nunca é guardado, logado nem devolvido à tela.
#
# - Escolher o funil de um formulário liga o recebimento da Página (assina o leadgen nela, pages_manage_metadata) e,
#   se pedido, traz quem preencheu nos últimos 90 dias (leads_retrieval), em segundo plano (ImportPastJob).
# - Parar tira só o leadgen da Página; os destinos ficam guardados para voltar.
# - Formulário arquivado não recebe ninguém novo: só traz quem já preencheu, sem destino e sem ligar a Página.
#
# Só no modo em que o token é do próprio cliente (Crm::MetaAdsConnection#own_token?): no `partner` o token é o da
# plataforma, e me/accounts traria Páginas de outros clientes.
#
# remember_pages: as Páginas lidas só ficam guardadas em crm_meta_ads_pages (id e nome) para quem pode mexer
# (meta_ads_manage). Quem só vê lê a lista sem gravar Página (#2357). Ligar a Página cria a linha dela (page_record).
class Crm::MetaAds::LeadForms::Hub
  LEADGEN = 'leadgen'.freeze
  ACTIVE = 'ACTIVE'.freeze
  SHOWN_STATUSES = %w[ACTIVE ARCHIVED].freeze

  def initialize(connection:, account:, remember_pages:, user: nil)
    @connection = connection
    @account = account
    @user = user
    @remember_pages = remember_pages
  end

  # visible_cards: os cards que a pessoa enxerga (nil quando ela não vê a lista de quem chegou).
  # visible_pipeline_ids: funis que ela enxerga, arquivados inclusive; destino em outro funil vai sem os nomes.
  def payload(pipelines:, visible_cards:, visible_pipeline_ids:)
    @visible_pipeline_ids = visible_pipeline_ids
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
  # Página que saiu do token (o cliente tirou o acesso): sem token dela não há o que desassinar; só esta conta para.
  def stop!(page_id)
    page = pages.find { |item| item['id'] == page_id.to_s }
    return stop_unlisted!(page_id) if page.nil?

    subscription(page).remove!([LEADGEN]) unless receiving_elsewhere?(page)
    page_record(page).update!(leadgen_receiving: false)
  rescue Crm::MetaAds::PageSubscription::Error => e
    raise_meta(e)
  end

  # O destino é gravado antes de ligar a Página: lead que chegar logo depois já tem para onde ir. Se a Meta recusar
  # ligar, o formulário volta ao destino que tinha.
  # Quem já preencheu vem em segundo plano (ImportPastJob), com a Página já ligada e o destino guardado: a resposta não
  # espera a leitura de milhares de leads, e falha nela não desfaz o destino.
  def save_destination!(form_id, pipeline:, stage:, import_past:)
    page, form = find_form!(form_id)
    raise Crm::MetaAds::LeadForms::Error, 'form_archived' unless form['status'] == ACTIVE

    record = form_record(page, form)
    previous = record.slice(:pipeline_id, :stage_id)
    record.update!(pipeline: pipeline, stage: stage)
    begin
      receive!(page['id'])
    rescue Crm::MetaAds::LeadForms::Error
      record.update!(previous)
      raise
    end
    enqueue_import(page, form, pipeline, stage, brought: false) if import_past
    { destination: destination_payload(record), importing: import_past }
  end

  def bring_past!(form_id, pipeline:, stage:)
    page, form = find_form!(form_id)
    raise Crm::MetaAds::LeadForms::Error, 'form_active' if form['status'] == ACTIVE

    form_record(page, form).update!(brought_pipeline: pipeline, brought_stage: stage)
    enqueue_import(page, form, pipeline, stage, brought: true)
    { importing: true, pipeline_name: pipeline.name, stage_name: stage.name }
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

  def stop_unlisted!(page_id)
    record = Crm::MetaAdsPage.find_by(account_id: @account.id, page_id: page_id.to_s)
    raise Crm::MetaAds::LeadForms::Error, 'page_not_found' if record.nil?

    record.update!(leadgen_receiving: false)
  end

  def receiving_elsewhere?(page)
    Crm::MetaAdsPage.leadgen_receiving.where(page_id: page['id']).where.not(account_id: @account.id).exists?
  end

  def enqueue_import(page, form, pipeline, stage, brought:)
    Crm::MetaAds::LeadForms::ImportPastJob.perform_later(@account.id, page['id'], form['id'], pipeline.id, stage.id,
                                                         user_id: @user&.id, brought: brought)
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
      remember(list)
      list
    end
  end

  def remember(list)
    Crm::MetaAdsPage.remember!(@account, list) if @remember_pages
  end

  def find_page!(page_id)
    pages.find { |page| page['id'] == page_id.to_s } || raise(Crm::MetaAds::LeadForms::Error, 'page_not_found')
  end

  # Página que a Meta não deixa ler agora não impede achar o formulário nas outras; se ele não aparece em nenhuma, o
  # motivo é a falha (e não "não existe").
  def find_form!(form_id)
    failure = nil
    pages.each do |page|
      form = forms_of(page).find { |item| item['id'] == form_id.to_s }
      return [page, form] if form
    rescue Crm::MetaAds::LeadForms::Error => e
      failure = e
    end
    raise failure || Crm::MetaAds::LeadForms::Error.new('form_not_found')
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
    base = { id: page['id'], name: page['name'], receiving: receiving }
    base.merge(forms: forms_of(page).map { |form| form_payload(page, form, records[form['id']]) })
  rescue Crm::MetaAds::LeadForms::Error => e
    # Uma Página que a Meta não deixa ler agora não derruba as outras: ela aparece sem formulários, com o motivo.
    base.merge(forms: [], error: e.code)
  end

  def form_payload(page, form, record)
    destination = record&.destination? ? destination_payload(record) : nil
    brought = brought_payload(record)
    past = destination || brought ? { count: 0, truncated: false } : past_count(page, form)
    {
      id: form['id'], name: form['name'], status: form['status'], leads_count: form['leads_count'].to_i,
      last_lead_at: last_lead_at(form['id']), destination: destination, brought: brought,
      past_count: past&.dig(:count), past_count_truncated: past&.dig(:truncated) || false
    }
  end

  def destination_payload(record)
    shown = visible_pipeline?(record.pipeline_id)
    { pipeline_id: record.pipeline_id, pipeline_name: (record.pipeline&.name if shown), stage_id: record.stage_id,
      stage_name: (record.stage&.name if shown) }
  end

  def brought_payload(record)
    return if record&.brought_count.blank?

    shown = visible_pipeline?(record.brought_pipeline_id)
    { count: record.brought_count, pipeline_name: (record.brought_pipeline&.name if shown),
      stage_name: (record.brought_stage&.name if shown) }
  end

  # Fora do payload (ao guardar ou trazer), o funil já passou pelo filtro do controller.
  def visible_pipeline?(pipeline_id)
    @visible_pipeline_ids.nil? || @visible_pipeline_ids.include?(pipeline_id)
  end

  def last_lead_at(form_id)
    @last_leads ||= Crm::MetaAdsLead.where(account_id: @account.id).group(:form_id).maximum(:received_at)
    @last_leads[form_id]&.iso8601
  end

  def past_count(page, form)
    Crm::MetaAds::LeadForms::PastLeads.cached_count(account: @account, page_id: page['id'], form_id: form['id'])
  end
end
