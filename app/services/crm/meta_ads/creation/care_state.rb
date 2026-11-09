# O que a gestão do anúncio diz sobre "Cuidar do anúncio" (#2778), na tela de detalhe:
#
# - `created_here`: o anúncio foi criado pelo Chat2You nesta conta de anúncios (opção a do Rodrigo, 09/11). Só nele a
#   tela mostra o cartão; nos outros, uma linha diz para usar o Gerenciador de Anúncios da Meta.
# - `creative_kind`: 'image' ou 'video' quando dá para trocar a foto ou o texto (Crm::MetaAds::Creation::CreativeChange);
#   nil em carrossel, post impulsionado ou quando a Meta não respondeu (aí só o duplicar). `creative_image` e
#   `creative_text`: a miniatura e o texto de agora, para o anúncio sem números no período (a tela não tem outra foto).
# - `can_swap_creative`: trocar no próprio anúncio (Crm::MetaAds::Creation::CreativeSwap); senão, a troca cria uma cópia.
# - `ads_manager_url`: o anúncio no Gerenciador de Anúncios, o mesmo endereço do consultor (Crm::MetaAds::Advisor::Advice).
#   É o "Abrir no Gerenciador" da linha que aparece nos anúncios criados fora.
class Crm::MetaAds::Creation::CareState
  NONE = { created_here: false, creative_kind: nil, can_swap_creative: false, creative_image: nil, creative_text: nil }.freeze

  def initialize(connection)
    @connection = connection
  end

  def payload(ad_id)
    record = Crm::MetaAds::Creation::Activation.new(@connection).created_here(ad_id)
    return NONE.merge(ads_manager_url: ads_manager_url(ad_id)) if record.nil?

    creative = read_creative(record)
    kind = Crm::MetaAds::Creation::CreativeChange.kind_of(creative['object_story_spec'])
    { created_here: true, creative_kind: kind, can_swap_creative: kind.present? && Crm::MetaAds::Creation::CreativeSwap.confirmed?,
      creative_image: creative['thumbnail_url'].presence, creative_text: (Crm::MetaAds::Creation::CreativeChange.text_of(creative) if kind),
      ads_manager_url: ads_manager_url(ad_id) }
  end

  private

  def ads_manager_url(ad_id)
    query = { act: @connection.ad_account_id.to_s.delete_prefix('act_'), selected_ad_ids: ad_id }.to_query
    "#{Crm::MetaAds::Advisor::Advice::ADS_MANAGER_URL}?#{query}"
  end

  # Post impulsionado não tem criativo próprio para trocar; sem leitura, {}.
  def read_creative(record)
    return {} if record.creative_id.blank? || record.source_post_id.present?

    result = Crm::MetaAds::Creation::Access.new(@connection).client.creative_spec(record.creative_id)
    result.ok ? result.data.to_h : {}
  end
end
