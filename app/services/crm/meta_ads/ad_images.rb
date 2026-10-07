# Imagem de cada anúncio no formato dele, para o painel mostrar o anúncio grande (#1088).
#
# Uma leitura da conta de anúncios lista os anúncios com o criativo: `image_url` é a imagem original. Anúncio em
# vídeo não tem imagem; para esses, uma chamada por criativo pede a miniatura em 1080 px (no máximo
# MAX_VIDEO_THUMBNAILS por rodada). Grava em Crm::MetaAdObject#thumbnail_url, junto com o nome e os IDs de
# conjunto e campanha.
#
# Só escreve o que veio: valor que a Meta não mandou (nome, imagem) mantém o que já estava na linha. A miniatura
# pequena e a prévia continuam com o NameResolver; por isso esta carga não mexe em `fetched_at`, que diz ao
# NameResolver que a linha já está completa.
class Crm::MetaAds::AdImages
  MAX_VIDEO_THUMBNAILS = 30
  KEPT_COLUMNS = %i[name campaign_id adset_id thumbnail_url].freeze
  ON_DUPLICATE = Arel.sql(
    (KEPT_COLUMNS.map { |column| "#{column} = COALESCE(EXCLUDED.#{column}, crm_meta_ad_objects.#{column})" } +
      ['object_type = EXCLUDED.object_type', 'updated_at = EXCLUDED.updated_at']).join(', ')
  )

  def initialize(connection)
    @connection = connection
  end

  # Quantos anúncios ficaram com imagem. nil quando a Meta recusou (o motivo vai para Insights::Failure).
  def refresh!
    return 0 unless @connection.insights_readable?

    result = client.ads_with_creatives(@connection.ad_account_id)
    unless result.ok
      Crm::MetaAds::Insights::Failure.handle!(@connection, result)
      return
    end

    records = Array(result.data.to_h['data']).filter_map { |row| record(row) }.uniq { |row| row[:meta_object_id] }
    return 0 if records.empty?

    # Lote já normalizado aqui; o índice único (conta, objeto) é a garantia de uma linha por anúncio.
    Crm::MetaAdObject.upsert_all(records, unique_by: :idx_crm_meta_ad_objects_account_object, on_duplicate: ON_DUPLICATE) # rubocop:disable Rails/SkipsModelValidations
    records.count { |row| row[:thumbnail_url].present? }
  end

  private

  def record(row)
    return unless row.is_a?(Hash) && Crm::MetaAds::NameResolver.meta_id?(row['id'])

    now = Time.current
    {
      account_id: @connection.account_id, meta_object_id: row['id'].to_s, object_type: 'ad',
      name: row['name'].to_s.first(Crm::MetaAdObject::NAME_LIMIT).presence, campaign_id: row['campaign_id'].presence&.to_s,
      adset_id: row['adset_id'].presence&.to_s, thumbnail_url: image_for(row['creative']), created_at: now, updated_at: now
    }
  end

  # Só a imagem grande. Sem ela (passou do limite de vídeos, a Meta falhou), nil: fica a que a linha já tinha.
  def image_for(creative)
    return unless creative.is_a?(Hash)

    https(creative['image_url']) || video_thumbnail(creative['id'])
  end

  def video_thumbnail(creative_id)
    return if creative_id.blank? || (@video_calls ||= 0) >= MAX_VIDEO_THUMBNAILS

    @video_calls += 1
    result = client.creative_thumbnail(creative_id)
    result.ok ? https(result.data.to_h['thumbnail_url']) : nil
  end

  def https(value)
    url = value.to_s.strip
    url.start_with?('https://') ? url.first(Crm::MetaAdObject::URL_LIMIT) : nil
  end

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end
end
