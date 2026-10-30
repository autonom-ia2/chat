# IA cuida dos comentários (#2212, B2): de onde vêm os comentários de um anúncio, lido no criativo dele na Meta (o mesmo
# que as abas de comentários do anúncio leem, Crm::MetaAds::InstagramComments e Crm::MetaAds::FacebookComments).
#
# Por rede, o post do criativo e a caixa da conta que o recebe:
# - Instagram: a mídia do anúncio (`effective_instagram_media_id`) e a caixa do Instagram da conta que a publica
#   (`instagram_user_id`), a mesma do webhook do comentário (Webhooks::InstagramCommentJob);
# - Facebook: o post da Página (`effective_object_story_id`) e a caixa do Messenger dessa Página na conta, a mesma do
#   webhook do `feed` (Crm::MetaAds::FacebookFeed#inbox_id).
#
# Só entram as redes com o post no criativo, a flag dos comentários da rede ligada (as mesmas das abas) e a caixa na
# conta: sem a caixa, o motor não teria por onde agir (Cuidar descarta o comentário sem `inbox_id`).
#
# `ler` devolve nil quando o anúncio não é da conta de anúncios da conexão (Crm::MetaAds::AdManagement#ad). Meta fora do
# ar levanta Crm::MetaAds::AdManagement::Error (`meta_unavailable`).
class Crm::MetaAds::ComentariosIa::Anuncio
  FLAGS = { 'instagram' => 'meta_ads_comentarios_instagram', 'facebook' => 'meta_ads_comentarios_facebook' }.freeze

  attr_reader :connection, :ad_id

  def self.ler(connection, ad_id)
    ad = Crm::MetaAds::AdManagement.new(connection).ad(ad_id.to_s)
    ad && new(connection, ad_id.to_s, ad['creative'].to_h)
  end

  def initialize(connection, ad_id, creative)
    @connection = connection
    @ad_id = ad_id
    @creative = creative
  end

  # { rede => { post_id:, inbox: } }, só as redes em que a IA pode cuidar.
  def redes
    @redes ||= { 'instagram' => instagram, 'facebook' => facebook }.select do |network, rede|
      rede && account.feature_enabled?(FLAGS[network])
    end
  end

  # Tem post em alguma rede ligada, mesmo sem a caixa na conta: diz à tela se falta a caixa ou o post.
  def post?
    FLAGS.any? { |network, flag| post_id(network).present? && account.feature_enabled?(flag) }
  end

  # O alvo só com ids (Painel, Fonte.do_alvo, LerAntigosJob e ResumoJob).
  def alvo
    { 'kind' => 'ad', 'ad_id' => @ad_id, 'networks' => redes.keys, 'post_ids' => redes.values.pluck(:post_id) }
  end

  private

  def instagram
    post_id = post_id('instagram')
    return if post_id.blank?

    channel = Channel::Instagram.find_by(account_id: @connection.account_id, instagram_id: @creative['instagram_user_id'].to_s)
    { post_id: post_id, inbox: channel.inbox } if channel&.inbox
  end

  def facebook
    post_id = post_id('facebook')
    return if post_id.blank?

    channel = Channel::FacebookPage.find_by(account_id: @connection.account_id, page_id: post_id.split('_').first)
    { post_id: post_id, inbox: channel.inbox } if channel&.inbox
  end

  def post_id(network)
    (network == 'instagram' ? @creative['effective_instagram_media_id'] : @creative['effective_object_story_id']).to_s.presence
  end

  def account
    @connection.account
  end
end
