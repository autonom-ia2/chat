# Anúncio novo (#2198, Fluxo 1). Campanha e grupo nascem ATIVOS e só o anúncio nasce PAUSADO: o gasto é zero até a pessoa
# tocar em "Ativar anúncio", e esse toque basta para pôr no ar. Os pontos obrigatórios do contrato
# (docs/crm/anuncios-meta-criar-2198.md):
#
# 1. `status: PAUSED` explícito no anúncio, nunca o padrão da Meta.
# 2. Relê o anúncio depois de criar; se não vier pausado (ou a leitura falhar), pausa na hora e registra na Auditoria.
# 3. Falha no meio desfaz o começo: apaga a campanha (o grupo e o anúncio vão junto) ou, se a Meta não deixar, arquiva.
#    Só quando isso dá certo a tela pode dizer "Nada foi criado".
# 4. Chave de idempotência por tentativa: a mesma chave devolve o mesmo anúncio e nunca cria duas campanhas.
# 5. Valor, datas, destino, lugar, público e mídia revalidados aqui (Crm::MetaAds::Creation::Draft).
class Crm::MetaAds::Creation::NewAd
  CENTS = 100
  REPAUSED_ACTION = 'meta_ads_create_repaused'.freeze
  OBJECTIVES = { 'WHATSAPP' => 'OUTCOME_ENGAGEMENT', 'MESSENGER' => 'OUTCOME_ENGAGEMENT',
                 'INSTAGRAM_DIRECT' => 'OUTCOME_ENGAGEMENT', 'WEBSITE' => 'OUTCOME_TRAFFIC' }.freeze
  SPECIAL_CATEGORY = 'FINANCIAL_PRODUCTS_SERVICES'.freeze

  def initialize(connection, user:)
    @connection = connection
    @account = connection.account
    @user = user
    @access = Crm::MetaAds::Creation::Access.new(connection)
  end

  def create!(params)
    draft = Crm::MetaAds::Creation::Draft.new(params, account: @account, zone: zone).validate!
    done = Crm::MetaAdsCreatedObject.find_by(account: @account, idempotency_key: draft[:idempotency_key], status: 'created')
    return result(done) if done

    raise Crm::MetaAds::Creation::Error, 'cannot_create' unless @access.can_create?

    page = find_page!(draft[:page_id])
    ensure_video_ready!(draft)
    record = claim!(draft)
    return result(record) if record.status == 'created'

    build!(record, draft, page)
    result(record)
  end

  private

  def client
    @access.client
  end

  def zone
    ActiveSupport::TimeZone[@connection.ad_account_timezone.to_s] || Time.zone
  end

  # A linha da tentativa. Já criada: devolve. Em andamento por outro pedido: recusa. Falhou antes: tenta de novo.
  def claim!(draft)
    record = Crm::MetaAdsCreatedObject.find_or_create_by!(account: @account, idempotency_key: draft[:idempotency_key]) do |row|
      row.assign_attributes(user_id: @user&.id, name: draft[:name], ad_account_id: @connection.ad_account_id, budget: budget(draft))
      @claimed = true
    end
    return record if @claimed || record.status == 'created'
    raise Crm::MetaAds::Creation::Error, 'in_progress' if record.status == 'creating'

    record.update!(status: 'creating', error_code: nil, campaign_id: nil, adset_id: nil, creative_id: nil, ad_id: nil)
    record
  rescue ActiveRecord::RecordNotUnique
    raise Crm::MetaAds::Creation::Error, 'in_progress'
  end

  def budget(draft)
    { 'kind' => 'daily', 'amount' => draft[:daily_amount], 'currency' => Crm::MetaAds::Creation::Options::CURRENCY,
      'start_time' => draft[:start_date].iso8601, 'end_time' => draft[:end_date]&.iso8601 }
  end

  def find_page!(page_id)
    Crm::MetaAds::Creation::Options.pages(client).find { |page| page[:id] == page_id } ||
      raise(Crm::MetaAds::Creation::Error, 'invalid_page')
  end

  # O vídeo sobe antes (Crm::MetaAds::Creation::Media) e a Meta processa sozinha. Ainda processando: a tela pede para
  # tentar de novo em um minuto, sem nada criado.
  def ensure_video_ready!(draft)
    [draft[:media], *draft[:cards]].select { |media| media[:kind] == 'video' }.each do |media|
      result = client.video_status(media[:video_id])
      raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok
      raise Crm::MetaAds::Creation::Error, 'video_processing' unless result.data.dig('status', 'video_status') == 'ready'
    end
  end

  def build!(record, draft, page)
    record.update!(campaign_id: meta_create!(:create_campaign, campaign_params(draft)))
    record.update!(adset_id: meta_create!(:create_adset, adset_params(draft, record.campaign_id)))
    record.update!(creative_id: meta_create!(:create_creative, creative_params(draft, page)))
    record.update!(ad_id: meta_create!(:create_ad, name: draft[:name], adset_id: record.adset_id,
                                                   creative: { creative_id: record.creative_id }.to_json, status: 'PAUSED'))
    ensure_paused!(record)
    record.update!(status: 'created')
  rescue Crm::MetaAds::Creation::Error => e
    raise rollback!(record, e)
  end

  def meta_create!(call, params)
    result = client.public_send(call, @connection.ad_account_id, params)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['id'].present?

    result.data['id'].to_s
  end

  def campaign_params(draft)
    { name: draft[:name], objective: OBJECTIVES.fetch(draft[:destination]), status: 'ACTIVE',
      special_ad_categories: (draft[:special_category] ? [SPECIAL_CATEGORY] : []).to_json,
      special_ad_category_country: (draft[:special_category] ? ['BR'].to_json : nil),
      is_adset_budget_sharing_enabled: false }.compact
  end

  def adset_params(draft, campaign_id)
    {
      name: draft[:name], campaign_id: campaign_id, status: 'ACTIVE', daily_budget: (draft[:daily_amount] * CENTS).round,
      billing_event: 'IMPRESSIONS', bid_strategy: 'LOWEST_COST_WITHOUT_CAP',
      optimization_goal: draft[:destination] == 'WEBSITE' ? 'LINK_CLICKS' : 'CONVERSATIONS',
      destination_type: draft[:destination], promoted_object: promoted_object(draft)&.to_json,
      targeting: Crm::MetaAds::Creation::Targeting.new(client).build(draft.values).to_json,
      start_time: start_time(draft[:start_date]).iso8601, end_time: end_time(draft[:end_date])&.iso8601
    }.compact
  end

  # Começa hoje: agora (a Meta recusa início no passado). Outro dia: à meia-noite no fuso da conta de anúncios.
  def start_time(date)
    date == zone.today ? zone.now : zone.local(date.year, date.month, date.day)
  end

  def end_time(date)
    date && zone.local(date.year, date.month, date.day, 23, 59)
  end

  def promoted_object(draft)
    case draft[:destination]
    when 'WHATSAPP' then { page_id: draft[:page_id], whatsapp_phone_number: draft[:whatsapp_number] }
    when 'WEBSITE' then nil
    else { page_id: draft[:page_id] }
    end
  end

  def creative_params(draft, page)
    story = Crm::MetaAds::Creation::Story.new(draft.values, instagram_id: page.dig(:instagram, :id))
    { name: draft[:name], object_story_spec: story.object_story_spec.to_json }
  end

  def ensure_paused!(record)
    reread = client.ad_management(record.ad_id)
    return if reread.ok && reread.data['effective_status'] == 'PAUSED'

    result = client.update_ad_status(record.ad_id, 'PAUSED')
    Audited.audit_class.create!(
      auditable: @account, user: @user, action: REPAUSED_ACTION,
      audited_changes: { 'ad_id' => record.ad_id, 'effective_status' => reread.ok ? reread.data['effective_status'] : 'unread',
                         'paused' => result.ok }
    )
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok
  end

  # Apaga a campanha; se não der, arquiva. Devolve o erro original dizendo se a Meta ficou como estava.
  def rollback!(record, error)
    return mark!(record, 'rolled_back', error, nothing_created: true) if record.campaign_id.blank?
    return mark!(record, 'rolled_back', error, nothing_created: true) if client.delete_object(record.campaign_id).ok

    archived = client.update_object(record.campaign_id, status: 'ARCHIVED').ok
    mark!(record, archived ? 'rolled_back' : 'rollback_failed', error, nothing_created: archived)
  end

  def mark!(record, status, error, nothing_created:)
    record.update!(status: status, error_code: error.code)
    Crm::MetaAds::Creation::Error.new(error.code, nothing_created: nothing_created)
  end

  def result(record)
    { ad_id: record.ad_id, name: record.name, status: 'PAUSED', budget: record.budget.merge('active_ads_count' => 0) }
  end
end
