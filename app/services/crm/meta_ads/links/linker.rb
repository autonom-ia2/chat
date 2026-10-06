# Liga os toques de anúncio da Meta de uma conversa ao anúncio, conjunto e campanha (#1073, F2b, CA-2.5).
#
# Toque de anúncio da Meta é o clique para o WhatsApp (`meta_ctwa`) ou o clique numa página do site (`site:…`)
# que traz algum sinal da Meta: ID de anúncio, conjunto ou campanha, o `fbclid` que a Meta põe no endereço, ou o
# `utm_source=meta` do texto que a tela manda colar nos anúncios. O resto (QR, Google, orgânico) fica de fora.
#
# O quanto sabemos (Crm::MetaAdLink::CERTAINTIES):
# - ID do anúncio no toque → `ad`; conjunto e campanha vêm do cache de nomes quando faltam;
# - só a campanha (ou o conjunto) por ID e o nome do anúncio em `utm_content` (o texto colado manda
#   {{ad.name}}) → procura o anúncio com esse nome dentro da campanha no cache que a coleta diária alimenta;
#   um único achado vira `ad_name`;
# - só campanha ou conjunto → `campaign`; nada → `unknown`.
#
# Gravação por upsert no (conversa, toque): regravar atualiza, nunca duplica. A lista de toques é cronológica e
# guarda os 20 primeiros (Ctwa::CampaignBuilder::MAX_TOUCHES descarta os seguintes, não roda a lista): o primeiro
# da lista é sempre a origem da conversa (`first_touch`).
class Crm::MetaAds::Links::Linker
  META_UTM_SOURCE = 'meta'.freeze
  SITE_PREFIX = Crm::MetaAds::TouchEnricher::SITE_SOURCE_PREFIX
  UPDATED_COLUMNS = %i[ad_account_id ad_id adset_id campaign_id origin certainty first_touch touched_at].freeze

  def self.origin(touch)
    return unless touch.is_a?(Hash)
    return 'whatsapp' if touch['source'] == Ctwa::CampaignBuilder::CTWA_SOURCE
    return unless touch['source_id'].to_s.start_with?(SITE_PREFIX)

    meta_signal = Crm::MetaAds::TouchEnricher.meta_ids?(touch) || touch['fbclid'].present? || touch['utm_source'] == META_UTM_SOURCE
    'site' if meta_signal
  end

  def self.meta_touch?(touch)
    origin(touch).present?
  end

  def initialize(conversation, connection: nil)
    @conversation = conversation
    @connection = connection || Crm::MetaAdsConnection.find_by(account_id: conversation.account_id)
  end

  # Quantas ligações foram gravadas.
  def perform
    records = touches.each_with_index.filter_map { |touch, index| record(touch, index.zero?) }
                     .index_by { |record| record[:touch_key] }.values
    return 0 if records.empty?

    # Lote já normalizado aqui; o índice único (conversa, toque) é a garantia de uma linha por toque.
    Crm::MetaAdLink.upsert_all(records, unique_by: :idx_crm_meta_ad_links_unique, update_only: UPDATED_COLUMNS) # rubocop:disable Rails/SkipsModelValidations
    records.size
  end

  private

  def touches
    list = @conversation.additional_attributes.to_h['campaign_touches']
    list.is_a?(Array) ? list : []
  end

  def record(touch, first)
    origin = self.class.origin(touch)
    key = origin && Ctwa::CampaignBuilder.dedup_key(touch)
    touched_at = origin && parse_time(touch['touched_at'])
    return if key.blank? || touched_at.nil?

    {
      account_id: @conversation.account_id, conversation_id: @conversation.id, touch_key: key.to_s,
      ad_account_id: @connection&.ad_account_id, origin: origin, first_touch: first, touched_at: touched_at
    }.merge(target(touch))
  end

  def target(touch)
    ids = Crm::MetaAds::TouchEnricher.ids_by_type(touch).transform_values(&:first)
    ad_id = ids['ad'] || ad_by_name(touch['utm_content'], ids['campaign'], ids['adset'])
    ad = ad_id && cached_ad(ad_id)

    {
      ad_id: ad_id, certainty: certainty_for(ids, ad_id),
      adset_id: ids['adset'] || ad&.adset_id, campaign_id: ids['campaign'] || ad&.campaign_id
    }
  end

  def certainty_for(ids, ad_id)
    return 'ad' if ids['ad'].present?
    return 'ad_name' if ad_id.present?
    return 'campaign' if ids['campaign'].present? || ids['adset'].present?

    'unknown'
  end

  # Nome do anúncio vindo do {{ad.name}} da Meta, dentro da campanha (ou do conjunto) que veio por ID. Só vale
  # quando exatamente um anúncio do cache tem esse nome ali.
  def ad_by_name(name, campaign_id, adset_id)
    return if name.blank? || (campaign_id.blank? && adset_id.blank?)

    scope = Crm::MetaAdObject.where(account_id: @conversation.account_id, object_type: 'ad', name: name.to_s)
    scope = campaign_id.present? ? scope.where(campaign_id: campaign_id) : scope.where(adset_id: adset_id)
    ids = scope.limit(2).pluck(:meta_object_id)
    ids.one? ? ids.first : nil
  end

  def cached_ad(ad_id)
    Crm::MetaAdObject.find_by(account_id: @conversation.account_id, meta_object_id: ad_id)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
