# Troca IDs de anúncio, conjunto e campanha da Meta pelos nomes (#1034).
#
# Primeiro o cache (crm_meta_ad_objects, válido por 7 dias); os IDs que faltam vão à Graph API
# num lote `?ids=` de até 50. Para anúncio, a mesma chamada traz o conjunto e a campanha, que
# também entram no cache.
#
# Erros da Graph (classes em Meta::AdsGraphClient):
# - token inválido (190) → credencial `invalid`, nada é resolvido;
# - falta de permissão (10, 2xx) → confere /me/permissions uma vez: sem `ads_read` concedida, é a
#   credencial (`invalid`); com ela, é um objeto fora do alcance do token e vale como erro de objeto;
# - erro de objeto (100, 803) → o lote é refeito ID a ID; o ID que falha sozinho entra no cache sem
#   nome (cache negativo) e não é buscado de novo por CACHE_TTL;
# - qualquer outro (limite de taxa, 5xx, rede) → para a busca nesta instância e devolve só o que já
#   está no cache, sem refazer ID a ID e sem mexer na credencial.
#
# Devolve { id => { name:, type:, campaign_name:, adset_name: } }.
class Crm::MetaAds::NameResolver
  BATCH_SIZE = 50
  MIN_ID_LENGTH = 6
  MAX_ID_LENGTH = 30
  FIELDS = {
    'ad' => 'name,adset{id,name},campaign{id,name}',
    'adset' => 'name,campaign{id,name}',
    'campaign' => 'name'
  }.freeze
  UNKNOWN_TYPE_FIELDS = 'name'.freeze

  class PermissionDenied < StandardError; end
  class GraphUnavailable < StandardError; end

  # ID da Meta: só dígitos, entre 6 e 30 caracteres. Conferido caractere a caractere, sem regex.
  def self.meta_id?(value)
    return false unless value.is_a?(String) || value.is_a?(Integer)

    text = value.to_s
    text.length.between?(MIN_ID_LENGTH, MAX_ID_LENGTH) && text.each_char.all? { |char| char.between?('0', '9') }
  end

  def initialize(account)
    @account = account
    @unavailable = false
    @ads_read_granted = nil
  end

  def resolve(ids, type: nil)
    ids = Array(ids).select { |id| self.class.meta_id?(id) }.map(&:to_s).uniq
    return {} if ids.empty?

    connection = Crm::MetaAdsConnection.active_for(@account.id)
    return {} if connection.blank?

    fetch_missing(connection, ids - fresh_ids(ids), type) unless @unavailable
    names_for(ids)
  rescue PermissionDenied
    {}
  rescue GraphUnavailable
    @unavailable = true
    names_for(ids)
  end

  private

  def fresh_ids(ids)
    Crm::MetaAdObject.fresh.where(account_id: @account.id, meta_object_id: ids).pluck(:meta_object_id)
  end

  def fetch_missing(connection, missing, type)
    return if missing.empty?

    client = Meta::AdsGraphClient.new(access_token: connection.access_token)
    fetched = missing.each_slice(BATCH_SIZE).map { |batch| fetch_batch(client, connection, batch, type) }
    connection.update!(last_checked_at: Time.current) if fetched.any?
  end

  # true quando a Graph respondeu algo útil para o lote.
  def fetch_batch(client, connection, batch, type)
    result = client.objects(batch, fields: FIELDS.fetch(type, UNKNOWN_TYPE_FIELDS))
    return store(result.data, batch, type) if result.ok

    deny!(connection, result) unless object_level_error?(client, result)
    return remember_missing(batch, type) if batch.one?

    batch.map { |id| fetch_batch(client, connection, [id], type) }.any?
  end

  # true quando o erro é do(s) objeto(s) e false quando é da credencial. Indisponibilidade lança.
  def object_level_error?(client, result)
    return true if result.object_error?
    return false if result.token_invalid?
    raise GraphUnavailable unless result.scope_error?

    ads_read_granted?(client)
  end

  # Uma conferência por instância: um lote de 50 IDs de outra conta de anúncios não vira 50 consultas.
  def ads_read_granted?(client)
    return @ads_read_granted unless @ads_read_granted.nil?

    check = client.permissions
    raise GraphUnavailable unless check.ok || check.token_invalid? || check.scope_error?

    @ads_read_granted = check.ok && Meta::AdsGraphClient.ads_read_granted?(check.data)
  end

  def deny!(connection, result)
    connection.mark_invalid!(result.error_message)
    raise PermissionDenied
  end

  # true quando a Graph trouxe algum nome. O ID do lote que não veio na resposta entra no cache negativo.
  def store(data, batch, type)
    rows = cache_rows(data, type)
    Crm::MetaAdObject.upsert_all(rows, unique_by: :idx_crm_meta_ad_objects_account_object) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    remember_missing(batch - rows.pluck(:meta_object_id), type)
    rows.any?
  end

  # Cache negativo: linha sem nome e com fetched_at de agora. fresh_ids a conta como resolvida e
  # names_for a deixa de fora, então o ID fica CACHE_TTL sem nova busca. Um nome já conhecido (de
  # antes de o anúncio ser apagado) é mantido: só fetched_at e updated_at mudam.
  def remember_missing(ids, type)
    return false if ids.empty?

    rows = ids.map { |id| row({ 'id' => id }, type, nil, nil) }
    Crm::MetaAdObject.upsert_all(rows, unique_by: :idx_crm_meta_ad_objects_account_object, update_only: %i[fetched_at]) # rubocop:disable Rails/SkipsModelValidations
    false
  end

  # O próprio objeto vem antes do conjunto e da campanha embutidos: o `uniq` fica com ele quando
  # o mesmo ID aparece nos dois papéis (o upsert não aceita a mesma chave duas vezes).
  def cache_rows(data, type)
    objects = data.to_h.values.select { |object| object.is_a?(Hash) && self.class.meta_id?(object['id']) }
    own = objects.map { |object| row(object, type, object.dig('campaign', 'id'), object.dig('adset', 'id')) }
    parents = objects.flat_map { |object| parent_rows(object) }
    (own + parents).uniq { |item| item[:meta_object_id] }
  end

  def parent_rows(object)
    adset = object['adset']
    campaign = object['campaign']
    [
      (row(adset, 'adset', campaign.to_h['id'], nil) if valid_parent?(adset)),
      (row(campaign, 'campaign', nil, nil) if valid_parent?(campaign))
    ].compact
  end

  def valid_parent?(object)
    object.is_a?(Hash) && self.class.meta_id?(object['id']) && object['name'].present?
  end

  def row(object, type, campaign_id, adset_id)
    now = Time.current
    {
      account_id: @account.id, meta_object_id: object['id'].to_s, object_type: type,
      name: object['name'].to_s.first(Crm::MetaAdObject::NAME_LIMIT).presence,
      campaign_id: campaign_id&.to_s, adset_id: adset_id&.to_s,
      fetched_at: now, created_at: now, updated_at: now
    }
  end

  def names_for(ids)
    objects = Crm::MetaAdObject.where(account_id: @account.id, meta_object_id: ids).where.not(name: nil).to_a
    return {} if objects.empty?

    parents = parent_names(objects)
    objects.to_h do |object|
      [object.meta_object_id, {
        name: object.name, type: object.object_type,
        campaign_name: parents[object.campaign_id], adset_name: parents[object.adset_id]
      }]
    end
  end

  def parent_names(objects)
    parent_ids = objects.flat_map { |object| [object.campaign_id, object.adset_id] }.compact.uniq
    return {} if parent_ids.empty?

    Crm::MetaAdObject.where(account_id: @account.id, meta_object_id: parent_ids).where.not(name: nil).pluck(:meta_object_id, :name).to_h
  end
end
