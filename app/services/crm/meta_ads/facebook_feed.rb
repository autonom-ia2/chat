# Comentário novo em post da Página, vindo do webhook `feed` (#2197), vira o evento comum dos comentários de anúncio,
# `meta_ads.comment_received` (o mesmo do Instagram, #2196), que o #2212 consome. Nada aqui é gravado: o comentário é
# dado de terceiro e quem consome decide o que guarda.
#
# - Só `item` comment com `verb` add. Edição, remoção, ocultação, curtida e post novo ficam de fora.
# - O eco da própria Página (as respostas que ela publica) não é comentário de cliente.
# - Uma vez por conta dona da Página (Crm::MetaAdsPage, #2195) com a flag `meta_ads_comentarios_facebook`; Página
#   sem dono nesta stack é ignorada (a outra stack recebe o mesmo corpo).
# - `inbox_id`: a caixa do Messenger dessa Página na conta, se houver (o #2212 usa para responder no privado).
# - `ad_id` vai nil: ligar o post ao anúncio pede uma chamada à Meta, e quem precisa liga do seu lado.
class Crm::MetaAds::FacebookFeed
  include Events::Types

  NETWORK = 'facebook'.freeze
  FLAG = 'meta_ads_comentarios_facebook'.freeze

  def initialize(page_id, value)
    @page_id = page_id
    @value = value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def perform
    return unless new_comment? && !page_echo?

    accounts.each { |account| dispatch(account) }
  end

  private

  def new_comment?
    @value['item'] == 'comment' && @value['verb'] == 'add' && @value['comment_id'].present?
  end

  def page_echo?
    @value.dig('from', 'id').to_s == @page_id
  end

  def accounts
    Account.where(id: Crm::MetaAdsPage.account_ids_for(@page_id)).select { |account| account.feature_enabled?(FLAG) }
  end

  def dispatch(account)
    Rails.configuration.dispatcher.dispatch(META_ADS_COMMENT_RECEIVED, Time.zone.now, payload(account))
  end

  def payload(account)
    {
      network: NETWORK, account_id: account.id, inbox_id: inbox_id(account), page_id: @page_id,
      post_id: @value['post_id'], ad_id: nil, comment_id: @value['comment_id'], parent_id: parent_id,
      from_id: @value.dig('from', 'id'), from_name: @value.dig('from', 'name'), text: @value['message'],
      created_time: created_time
    }
  end

  # Comentário de primeiro nível chega com o post como pai.
  def parent_id
    parent = @value['parent_id']
    parent == @value['post_id'] ? nil : parent
  end

  def created_time
    time = @value['created_time']
    time.is_a?(Integer) ? Time.zone.at(time) : nil
  end

  def inbox_id(account)
    Channel::FacebookPage.find_by(account_id: account.id, page_id: @page_id)&.inbox&.id
  end
end
