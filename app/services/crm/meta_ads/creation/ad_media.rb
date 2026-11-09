# A mídia do anúncio no Instagram (#2804): o post do Instagram impulsionado por aqui vira um anúncio cujos comentários
# ficam noutra mídia (`effective_instagram_media_id` do criativo), uma por anúncio. O "Esperando você" de Seus posts
# (SeusPosts::Esperando) lê os comentários dela sem ler o anúncio na Meta a cada vez: o id fica guardado aqui, escrito
# por quem já lê o anúncio (Crm::MetaAds::Creation::ActivationSweep, de hora em hora, e a lista de pausados). O id não
# muda depois de criado; se sair do cache, a próxima rodada o grava de novo, e até lá o post conta só os comentários
# dele.
module Crm::MetaAds::Creation::AdMedia
  TTL = 120.days
  NETWORK = 'instagram'.freeze

  def self.key(account_id, ad_id)
    "crm_meta_ads:ad_media:v1:#{account_id}:#{ad_id}"
  end

  # record: Crm::MetaAdsCreatedObject; meta_ad: a leitura do anúncio (Meta::AdsGraphClient#ad_management).
  def self.remember(record, meta_ad)
    media_id = meta_ad.to_h.dig('creative', 'effective_instagram_media_id').to_s
    return if record.source_post_network != NETWORK || !graph_id?(media_id)

    Rails.cache.write(key(record.account_id, record.ad_id), media_id, expires_in: TTL)
  end

  # Só dígitos: o id vai no caminho da chamada de comentários (SeusPosts::Esperando).
  def self.graph_id?(value)
    value.present? && value.each_char.all? { |char| char.between?('0', '9') }
  end

  def self.known?(account_id, ad_id)
    Rails.cache.exist?(key(account_id, ad_id))
  end

  # { ad_id => media_id }, só dos que estão guardados.
  def self.of(account_id, ad_ids)
    keys = Array(ad_ids).map(&:to_s).index_by { |ad_id| key(account_id, ad_id) }
    return {} if keys.empty?

    Rails.cache.read_multi(*keys.keys).transform_keys { |chave| keys[chave] }
  end
end
