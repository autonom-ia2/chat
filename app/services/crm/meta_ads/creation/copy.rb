# Duplicar um anúncio criado aqui (#2778, Fluxo 5; opção a do Rodrigo, 09/11: só os criados pelo Chat2You). A cópia é
# uma campanha nova, pausada, com o grupo e o orçamento próprios, iguais aos do original: copiar só o anúncio dividiria
# o dinheiro do grupo. Com `creative` ({ text, media? }), a cópia já nasce com a foto ou o texto novos ("Trocar a foto
# (cria uma cópia)"), e o original continua como está.
#
# As chamadas, todas com `status_option: PAUSED`:
# 1. `POST /{campaign_id}/copies` sem os níveis de baixo (`deep_copy: false`). O nome da cópia termina com
#    " - Cópia [marca]": é pela marca que o desfazer acha a campanha se a resposta se perder.
# 2. `POST /{adset_id}/copies` para dentro da campanha nova, começando agora (o início do original já passou).
# 3. O criativo: o mesmo do original, ou um novo (Crm::MetaAds::Creation::CreativeChange).
# 4. O anúncio, pausado, no grupo novo (`POST act_{id}/ads`, a mesma chamada do criar).
# Depois, relê os três e pausa o que não vier pausado (Crm::MetaAds::Creation::Levels), como o criar (ponto 2).
#
# Idempotência, desfazer e "não confirmada" são os do criar (Crm::MetaAds::Creation::Attempt): uma linha `kind: copy`
# em Crm::MetaAdsCreatedObject, que também faz a cópia aparecer em "Pausados" e ser ativada pelos três níveis.
class Crm::MetaAds::Creation::Copy
  KIND = 'copy'.freeze
  # Vai para a Meta, no nome da cópia (como a marca da tentativa).
  SUFFIX = ' - Cópia'.freeze
  NAME_LIMIT = Crm::MetaAds::Creation::Draft::NAME_LIMIT

  # true quando esta chamada criou a cópia (a mesma chave de novo devolve a que já existia).
  attr_reader :created_now

  def initialize(connection, user:)
    @connection = connection
    @account = connection.account
    @user = user
    @access = Crm::MetaAds::Creation::Access.new(connection)
    @attempt = Crm::MetaAds::Creation::Attempt.new(connection, client, user: user)
  end

  def copy!(ad_id, params)
    params = params.to_h.with_indifferent_access
    source = Crm::MetaAds::Creation::Activation.new(@connection).created_here(ad_id) || raise(Crm::MetaAds::Creation::Error, 'ad_not_found')
    key = Crm::MetaAds::Creation::Draft.key!(params[:idempotency_key])
    change = params[:creative].present? ? Crm::MetaAds::Creation::CreativeChange.from_params(params[:creative]) : nil
    @digest = digest(source, change)
    done = same_request!(key)
    return result(done) if done&.status == 'created'

    build_copy!(source, key, change)
  end

  private

  # A chave é de um pedido só: a mesma chave com outro anúncio, outro criativo ou de um anúncio novo é recusa.
  def same_request!(key)
    record = Crm::MetaAdsCreatedObject.find_by(account: @account, idempotency_key: key)
    return if record.nil?
    raise Crm::MetaAds::Creation::Error, 'invalid_params' unless record.kind == KIND && record.request_digest == @digest

    record
  end

  def client
    @access.client
  end

  def build_copy!(source, key, change)
    raise Crm::MetaAds::Creation::Error, 'cannot_change' unless @access.can_change_ads?

    @budget = Crm::MetaAds::Creation::Budget.new(@connection).read(source.ad_id)
    raise Crm::MetaAds::Creation::Error, 'cannot_change' unless @budget[:can_change]

    @end_time = end_time!(@budget[:end_time])
    creative = change && new_creative_params(source, change)
    record = @attempt.claim!(key, { kind: KIND, name: copy_name(source), budget: stored_budget, request_digest: @digest,
                                    source_post_id: source.source_post_id, source_post_network: source.source_post_network })
    return result(record) if record.status == 'created'

    build!(record, source, creative)
    @created_now = true
    result(record)
  end

  # O fim do original vale para a cópia; já passou, não há o que copiar (a Meta recusaria).
  def end_time!(value)
    return if value.blank?

    time = Time.zone.parse(value.to_s)
    raise Crm::MetaAds::Creation::Error, 'invalid_dates' unless time && time > Time.current

    value
  end

  # O criativo novo sai do de agora, relido antes de gravar a tentativa: recusa aqui é "nada foi criado".
  def new_creative_params(source, change)
    raise Crm::MetaAds::Creation::Error, 'invalid_creative' if source.creative_id.blank? || source.source_post_id.present?

    read = client.creative_spec(source.creative_id)
    raise Crm::MetaAds::Creation::Error.from_result(read) unless read.ok

    change.creative_params(read.data, name: copy_name(source))
  end

  def copy_name(source)
    "#{source.name.to_s.first(NAME_LIMIT - SUFFIX.length)}#{SUFFIX}"
  end

  def stored_budget
    { 'kind' => @budget[:kind], 'amount' => @budget[:amount], 'currency' => @budget[:currency],
      'start_time' => start_time, 'end_time' => @end_time }
  end

  def start_time
    @start_time ||= Time.current.iso8601
  end

  # Duas cópias do mesmo anúncio, com o mesmo criativo, ao mesmo tempo (outra aba): só uma (Crm::MetaAds::Creation::Twin).
  def digest(source, change)
    Digest::SHA256.hexdigest([KIND, source.ad_id, change&.values].to_json)
  end

  def build!(record, source, creative)
    step!(record, :campaign_id, 'copied_campaign_id') { client.copy_campaign(source.campaign_id, campaign_copy_params(record)) }
    step!(record, :adset_id, 'copied_adset_id') { client.copy_adset(source.adset_id, adset_copy_params(record)) }
    build_ad!(record, source, creative)
    @reread = Crm::MetaAds::Creation::Levels.new(client, account: @account, user: @user).ensure_paused!(record)
    record.update!(status: 'created')
  rescue Crm::MetaAds::Creation::Error => e
    drop_new_creative(record, source)
    raise @attempt.rollback!(record, e, unknown: @campaign_unknown)
  rescue StandardError => e
    drop_new_creative(record, source)
    @attempt.rollback!(record, Crm::MetaAds::Creation::Error.new('meta_refused'), unknown: @campaign_unknown)
    raise e
  end

  # O desfazer apaga a campanha; o criativo novo não vai junto. O do original nunca é apagado. Sem conseguir, ele fica
  # solto na conta, sem gastar nada.
  def drop_new_creative(record, source)
    return if record.creative_id.blank? || record.creative_id == source.creative_id

    client.delete_object(record.creative_id)
  end

  # O criativo do original, ou o novo; e o anúncio pausado no grupo da cópia.
  def build_ad!(record, source, creative)
    if creative
      step!(record, :creative_id, 'id') { client.create_creative(@connection.ad_account_id, creative) }
    else
      record.update!(creative_id: source.creative_id)
    end
    step!(record, :ad_id, 'id') do
      client.create_ad(@connection.ad_account_id, name: record.name, adset_id: record.adset_id,
                                                  creative: { creative_id: record.creative_id }.to_json, status: 'PAUSED')
    end
    record.update!(updated_at: Time.current)
  end

  # Como no criar (Crm::MetaAds::Creation::NewAd#step!): renova a linha, chama a Meta e grava o id que voltou. A campanha
  # sem resposta pode ter sido copiada mesmo assim (`@campaign_unknown`).
  def step!(record, column, id_field)
    record.update!(updated_at: Time.current)
    result = yield
    id = result.data[id_field].presence if result.ok
    @campaign_unknown = column == :campaign_id && id.nil? && (result.ok || result.transient?)
    raise Crm::MetaAds::Creation::Error.from_result(result) if id.nil?

    record.update!(column => id.to_s)
  end

  def campaign_copy_params(record)
    { deep_copy: false, status_option: 'PAUSED',
      rename_options: { rename_strategy: 'ONLY_TOP_LEVEL_RENAME',
                        rename_suffix: "#{SUFFIX} [#{Crm::MetaAds::Creation::CampaignUndo.mark(record)}]" }.to_json }
  end

  def adset_copy_params(record)
    { campaign_id: record.campaign_id, deep_copy: false, status_option: 'PAUSED',
      rename_options: { rename_strategy: 'NO_RENAME' }.to_json, start_time: start_time, end_time: @end_time }.compact
  end

  # Como o criar: pausada, com o orçamento do original, e `in_review` pela releitura (a mesma chave de novo: false).
  def result(record)
    ad = @reread.to_h['ad'].to_h
    { ad_id: record.ad_id, campaign_id: record.campaign_id, name: record.name, status: 'PAUSED', budget: budget_payload(record),
      in_review: Crm::MetaAds::AdManagement.in_review?(ad['status'], ad['effective_status']) }
  end

  def budget_payload(record)
    stored = record.budget.merge('active_ads_count' => 0, 'ads_count' => 1, 'level' => 'adset', 'started' => false,
                                 'object_id' => record.adset_id, 'adset_id' => record.adset_id)
    return stored unless @budget

    stored.merge('object_name' => @budget[:object_name], 'today' => @budget[:today])
  end
end
