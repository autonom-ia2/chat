# Comentário novo em post da Página, vindo do webhook `feed` (#2197), vira o evento comum dos comentários,
# `meta_ads.comment_received` (o mesmo do Instagram, #2196), que o #2212 consome. Nada aqui é gravado.
#
# - Vale para todo post da Página, de anúncio ou orgânico (o Seus posts F2, #2305, usa o orgânico): `ad_id` vai nil,
#   porque ligar o post ao anúncio pede outra chamada à Meta, e quem precisa liga do seu lado.
# - O payload leva só ids, nunca o texto nem o nome de quem comentou: o evento passa pelo EventDispatcherJob, cujos
#   argumentos o Sidekiq guarda em claro no Redis e o ActiveJob escreve no log. Quem consome lê o comentário por
#   Crm::MetaAds::FacebookComments#comment (3 chamadas à Graph: permissões, token da Página e o comentário). Aqui,
#   nenhuma.
# - Só `item` comment com `verb` add. Edição, remoção, ocultação, curtida e post novo ficam de fora.
# - O eco da própria Página (as respostas que ela publica) não é comentário de cliente. Sem leitura na Graph aqui, o
#   eco é reconhecido só pelo `from.id` do webhook (= id da Página).
# - Uma vez por conta dona da Página (Crm::MetaAdsPage, #2195) com a flag `meta_ads_comentarios_facebook`. A Página
#   entra nessa tabela quando alguém da conta abre a aba Facebook pela primeira vez: antes disso, não há evento.
#   Página sem dono nesta stack é ignorada (a outra stack recebe o mesmo corpo).
# - Aqui não se confere conexão ativa nem `pages_read_user_content`: o evento sai mesmo assim, só com ids. Esse filtro é
#   do consumidor, por FacebookComments#comment, que só lê com a leitura concedida e em Página da conta (nil se não).
# - O mesmo comentário de novo em DEDUP (webhook reenviado) não sai duas vezes. Erro numa conta não tira o evento das
#   outras: vai ao rastreador e solta a chave. Quem consome não deve contar com entrega única.
# - `inbox_id`: a caixa do Messenger dessa Página na conta, se houver.
class Crm::MetaAds::FacebookFeed
  include Events::Types

  NETWORK = 'facebook'.freeze
  FLAG = 'meta_ads_comentarios_facebook'.freeze
  DEDUP = 10.minutes

  def initialize(page_id, value)
    @page_id = page_id
    @value = value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def perform
    return unless new_comment? && @value['from_id'].to_s != @page_id

    accounts.each { |account| publish(account) if first_time?(account) }
  end

  private

  def new_comment?
    @value['item'] == 'comment' && @value['verb'] == 'add' && @value['comment_id'].is_a?(String) && @value['post_id'].is_a?(String)
  end

  def accounts
    Account.where(id: Crm::MetaAdsPage.account_ids_for(@page_id)).select { |account| account.feature_enabled?(FLAG) }
  end

  def publish(account)
    Rails.configuration.dispatcher.dispatch(META_ADS_COMMENT_RECEIVED, Time.zone.now, payload(account))
  rescue StandardError => e
    Redis::Alfred.delete(dedup_key(account))
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  def dedup_key(account)
    "facebook:comment_received:#{account.id}:#{@value['comment_id']}"
  end

  def first_time?(account)
    Redis::Alfred.set(dedup_key(account), 1, nx: true, ex: DEDUP.to_i) ? true : false
  end

  def payload(account)
    {
      network: NETWORK, account_id: account.id, inbox_id: inbox_id(account), page_id: @page_id,
      post_id: @value['post_id'], ad_id: nil, comment_id: @value['comment_id'], parent_id: parent_id,
      from_id: @value['from_id'], created_time: created_time
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
