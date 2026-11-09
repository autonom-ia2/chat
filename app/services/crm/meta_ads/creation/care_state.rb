# O que a gestão do anúncio diz sobre "Cuidar do anúncio" (#2778), na tela de detalhe:
#
# - `created_here`: o anúncio foi criado pelo Chat2You nesta conta de anúncios (opção a do Rodrigo, 09/11). Só nele a
#   tela mostra o cartão; nos outros, uma linha diz para usar o Gerenciador de Anúncios da Meta.
# - `creative_kind`: 'image' ou 'video' quando dá para trocar a foto ou o texto no próprio anúncio
#   (Crm::MetaAds::Creation::CreativeChange e CreativeSwap; ligado para todos em #2804); nil em carrossel, post
#   impulsionado ou quando a Meta não respondeu (aí só o duplicar). Se a Meta recusar a troca, a tela oferece a cópia. `creative_image` e
#   `creative_text`: a miniatura e o texto de agora, para o anúncio sem números no período (a tela não tem outra foto).
# - `active_copy`: { ad_id, name } da cópia com a foto ou o texto novos que está no ar enquanto este também está
#   (Crm::MetaAds::Creation::ActiveCopy, #2804). Com ela, a tela mostra "Pausar o original", mesmo depois de recarregar.
# - `ads_manager_url`: o anúncio no Gerenciador de Anúncios, o mesmo endereço do consultor (Crm::MetaAds::Advisor::Advice).
#   É o "Abrir no Gerenciador" da linha que aparece nos anúncios criados fora.
#
# A leitura do criativo fica guardada por CACHE_FOR, por conta e anúncio: cada abertura do detalhe chamava a Graph e
# gastava o limite de uso da Meta. Só leitura que deu certo fica guardada. Duplicar e trocar apagam (`forget`).
class Crm::MetaAds::Creation::CareState
  NONE = { created_here: false, creative_kind: nil, creative_image: nil, creative_text: nil, active_copy: nil }.freeze

  CACHE_FOR = 5.minutes

  def self.cache_key(account_id, ad_id)
    "meta_ads:care_state:creative:#{account_id}:#{ad_id}"
  end

  def self.forget(account_id, ad_id)
    Redis::Alfred.delete(cache_key(account_id, ad_id))
    Redis::Alfred.delete(Crm::MetaAds::Creation::ActiveCopy.cache_key(account_id, ad_id))
  end

  def initialize(connection)
    @connection = connection
  end

  # `original_status`: a situação escolhida deste anúncio, já lida pela gestão. Só ativo pode ter a cópia no lugar.
  def payload(ad_id, original_status: nil)
    record = Crm::MetaAds::Creation::Activation.new(@connection).created_here(ad_id)
    return NONE.merge(ads_manager_url: ads_manager_url(ad_id)) if record.nil?

    creative = read_creative(record)
    kind = Crm::MetaAds::Creation::CreativeChange.kind_of(creative['object_story_spec'])
    { created_here: true, creative_kind: kind, creative_image: creative['thumbnail_url'].presence,
      creative_text: (Crm::MetaAds::Creation::CreativeChange.text_of(creative) if kind), ads_manager_url: ads_manager_url(ad_id),
      active_copy: (Crm::MetaAds::Creation::ActiveCopy.new(@connection).find(ad_id) if original_status == 'ACTIVE') }
  end

  private

  def ads_manager_url(ad_id)
    query = { act: @connection.ad_account_id.to_s.delete_prefix('act_'), selected_ad_ids: ad_id }.to_query
    "#{Crm::MetaAds::Advisor::Advice::ADS_MANAGER_URL}?#{query}"
  end

  # Post impulsionado não tem criativo próprio para trocar; sem leitura, {}.
  def read_creative(record)
    return {} if record.creative_id.blank? || record.source_post_id.present?

    key = self.class.cache_key(@connection.account_id, record.ad_id)
    cached = fresh(Redis::Alfred.get(key))
    return cached if cached

    result = Crm::MetaAds::Creation::Access.new(@connection).client.creative_spec(record.creative_id)
    return {} unless result.ok

    Redis::Alfred.setex(key, { 'read_at' => Time.current.to_i, 'creative' => result.data.to_h }.to_json, CACHE_FOR)
    result.data.to_h
  end

  # A hora da leitura vai junto: o prazo vale pelo relógio da aplicação, e o do Redis só limpa o que sobrou.
  def fresh(raw)
    return if raw.blank?

    stored = JSON.parse(raw)
    stored['creative'] if Time.current.to_i - stored['read_at'].to_i < CACHE_FOR.to_i
  end
end
