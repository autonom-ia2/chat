# Anúncio novo (#2198, Fluxo 1). Campanha e grupo nascem ATIVOS e só o anúncio nasce PAUSADO: o gasto é zero até a pessoa
# tocar em "Ativar anúncio", e esse toque basta para pôr no ar. Os pontos obrigatórios do contrato
# (docs/crm/anuncios-meta-criar-2198.md):
#
# 1. `status: PAUSED` explícito no anúncio, nunca o padrão da Meta.
# 2. Relê o anúncio depois de criar; se não vier pausado (ou a leitura falhar), pausa na hora e registra na Auditoria.
# 3. Falha no meio desfaz o começo: apaga a campanha (o grupo e o anúncio vão junto) ou, se a Meta não deixar, arquiva.
#    Só quando isso dá certo a tela pode dizer "Nada foi criado".
# 4. Chave de idempotência por tentativa (Crm::MetaAds::Creation::Attempt): a mesma chave devolve o mesmo anúncio e
#    nunca cria duas campanhas. Tentativa que ficou na Meta é desfeita antes de tentar de novo; se nem assim der, recusa
#    sem criar outra campanha.
# 5. Valor, datas, destino, lugar, público e mídia revalidados aqui (Crm::MetaAds::Creation::Draft).
# 6. Moeda lida na Meta antes de criar: só real (os limites são em reais). Sem conseguir ler, não cria.
# 7. A intenção fica gravada antes da primeira chamada: a linha `creating` e o nome da campanha com a marca da tentativa
#    (Crm::MetaAds::Creation::CampaignUndo). Campanha sem resposta: o desfazer procura pela marca; busca vazia não é
#    "Nada foi criado", é `unconfirmed` (a tela pede para conferir no Gerenciador de Anúncios).
class Crm::MetaAds::Creation::NewAd
  REPAUSED_ACTION = 'meta_ads_create_repaused'.freeze
  OBJECTIVES = { 'WHATSAPP' => 'OUTCOME_ENGAGEMENT', 'MESSENGER' => 'OUTCOME_ENGAGEMENT',
                 'INSTAGRAM_DIRECT' => 'OUTCOME_ENGAGEMENT', 'WEBSITE' => 'OUTCOME_TRAFFIC' }.freeze
  SPECIAL_CATEGORY = 'FINANCIAL_PRODUCTS_SERVICES'.freeze

  # true quando esta chamada criou o anúncio (a mesma chave de novo devolve o que já existia).
  attr_reader :created_now

  def initialize(connection, user:)
    @connection = connection
    @account = connection.account
    @user = user
    @access = Crm::MetaAds::Creation::Access.new(connection)
    @attempt = Crm::MetaAds::Creation::Attempt.new(connection, @access.client, user: user)
  end

  def create!(params)
    done = already_created(params)
    return result(done) if done

    draft = Crm::MetaAds::Creation::Draft.new(params, account: @account, zone: zone).validate!

    raise Crm::MetaAds::Creation::Error, 'cannot_create' unless @access.can_create?
    raise Crm::MetaAds::Creation::Error, 'currency_not_supported' unless currency == Crm::MetaAds::Creation::Money::CURRENCY

    page = find_page!(draft[:page_id])
    ensure_video_ready!(draft)
    # O público (estados → regiões da Meta) se resolve antes de criar qualquer coisa.
    @targeting = Crm::MetaAds::Creation::Targeting.new(client).build(draft.values)
    record = @attempt.claim!(draft[:idempotency_key], name: draft[:name], budget: budget(draft))
    return result(record) if record.status == 'created'

    build!(record, draft, page)
    @created_now = true
    result(record)
  end

  private

  def client
    @access.client
  end

  def zone
    @zone ||= Crm::MetaAds::Creation::AccountZone.new(@connection, client).zone
  end

  def currency
    Crm::MetaAds::Creation::Money.currency!(client, @connection.ad_account_id)
  end

  # A mesma chave de um anúncio já criado devolve o que existe, sem nenhuma chamada à Meta.
  def already_created(params)
    key = params.to_h.with_indifferent_access[:idempotency_key].to_s.strip
    key.present? && Crm::MetaAdsCreatedObject.find_by(account: @account, idempotency_key: key, status: 'created')
  end

  def budget(draft)
    { 'kind' => 'daily', 'amount' => Crm::MetaAds::Creation::Money.text(draft[:daily_amount]),
      'currency' => Crm::MetaAds::Creation::Money::CURRENCY,
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
    step!(record, :campaign_id, :create_campaign, campaign_params(draft, record))
    step!(record, :adset_id, :create_adset, adset_params(draft, record.campaign_id))
    step!(record, :creative_id, :create_creative, creative_params(draft, page))
    step!(record, :ad_id, :create_ad, name: draft[:name], adset_id: record.adset_id,
                                      creative: { creative_id: record.creative_id }.to_json, status: 'PAUSED')
    alive!(record)
    ensure_paused!(record)
    record.update!(status: 'created')
  rescue Crm::MetaAds::Creation::Error => e
    raise @attempt.rollback!(record, e, unknown: @campaign_unknown)
  rescue StandardError => e
    @attempt.rollback!(record, Crm::MetaAds::Creation::Error.new('meta_refused'), unknown: @campaign_unknown)
    raise e
  end

  # Renova a linha (sinal de vida da tentativa) antes de chamar a Meta e grava o id que voltou. O id fica na memória
  # mesmo se gravar falhar, para o desfazer achar. Campanha sem resposta (tempo esgotado, falha da Meta, resposta sem
  # id): pode ter sido criada mesmo assim (`@campaign_unknown`). Recusa clara da Meta: não foi.
  def step!(record, column, call, params)
    alive!(record)
    result = client.public_send(call, @connection.ad_account_id, params)
    id = result.data['id'].presence if result.ok
    @campaign_unknown = column == :campaign_id && id.nil? && (result.ok || result.transient?)
    raise Crm::MetaAds::Creation::Error.from_result(result) if id.nil?

    record.assign_attributes(column => id.to_s)
    record.save!
  end

  def alive!(record)
    record.update!(updated_at: Time.current)
  end

  # O nome leva a marca da tentativa: é por ela que o desfazer acha a campanha se o id se perdeu.
  def campaign_params(draft, record)
    { name: Crm::MetaAds::Creation::CampaignUndo.name_for(record), objective: OBJECTIVES.fetch(draft[:destination]), status: 'ACTIVE',
      special_ad_categories: (draft[:special_category] ? [SPECIAL_CATEGORY] : []).to_json,
      special_ad_category_country: (draft[:special_category] ? ['BR'].to_json : nil),
      is_adset_budget_sharing_enabled: false }.compact
  end

  def adset_params(draft, campaign_id)
    {
      name: draft[:name], campaign_id: campaign_id, status: 'ACTIVE', daily_budget: Crm::MetaAds::Creation::Money.cents(draft[:daily_amount]),
      billing_event: 'IMPRESSIONS', bid_strategy: 'LOWEST_COST_WITHOUT_CAP',
      optimization_goal: draft[:destination] == 'WEBSITE' ? 'LINK_CLICKS' : 'CONVERSATIONS',
      destination_type: draft[:destination], promoted_object: promoted_object(draft)&.to_json,
      targeting: @targeting.to_json,
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
    audit_repause(record, reread, result)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok
  end

  # A pausa já aconteceu (ou não) na Meta: falha ao gravar a Auditoria vai para o rastreador, nunca impede a pausa nem
  # o desfazer.
  def audit_repause(record, reread, result)
    Audited.audit_class.create!(
      auditable: @account, user: @user, action: REPAUSED_ACTION,
      audited_changes: { 'ad_id' => record.ad_id, 'effective_status' => reread.ok ? reread.data['effective_status'] : 'unread',
                         'paused' => result.ok }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end

  def result(record)
    { ad_id: record.ad_id, name: record.name, status: 'PAUSED', budget: record.budget.merge('active_ads_count' => 0) }
  end
end
