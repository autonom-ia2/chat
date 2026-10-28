# Comentário novo em post da Página, vindo do webhook `feed` (#2197), vira o evento comum dos comentários de anúncio,
# `meta_ads.comment_received` (o mesmo do Instagram, #2196), que o #2212 consome. Nada aqui é gravado: o comentário é
# dado de terceiro e quem consome decide o que guarda.
#
# - Chegam só os ids (Webhooks::FacebookFeedJob.webhook_value). O texto e o nome de quem comentou são lidos na Graph,
#   com o token da Página pedido pela conexão de anúncios da conta (Crm::MetaAds::FacebookComments#comment).
# - Só `item` comment com `verb` add. Edição, remoção, ocultação, curtida e post novo ficam de fora.
# - O eco da própria Página (as respostas que ela publica) não é comentário de cliente.
# - Uma vez por conta dona da Página (Crm::MetaAdsPage, #2195) com a flag `meta_ads_comentarios_facebook`. A Página
#   entra nessa tabela quando alguém da conta abre a aba Facebook pela primeira vez: antes disso, não há evento.
#   Página sem dono nesta stack é ignorada (a outra stack recebe o mesmo corpo).
# - Conta sem conexão ativa, sem a leitura concedida ou cuja leitura a Meta recusa fica sem o evento. Meta fora do ar
#   sobe para o retry do job.
# - O mesmo comentário de novo em DEDUP (webhook reenviado) não sai duas vezes. A chave só fica se o evento saiu.
#   Erro numa conta não tira o evento das outras: vai ao rastreador, e Meta fora do ar sobe no fim para o retry, que
#   só repete as contas que ficaram sem evento (as outras estão no dedupe). Quem consome (#2212) não deve contar com
#   entrega única: o dedupe é por 10 min, e um listener que falhe no meio solta a chave.
# - `inbox_id`: a caixa do Messenger dessa Página na conta, se houver (o #2212 usa para responder no privado).
# - `ad_id` vai nil: ligar o post ao anúncio pede outra chamada à Meta, e quem precisa liga do seu lado.
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

    unavailable = accounts.filter_map { |account| publish_alone(account) }.first
    raise unavailable if unavailable
  end

  private

  # Uma conta por vez: devolve a Meta fora do ar (FacebookComments só deixa sair `meta_unavailable`) para o retry; outro
  # erro vai ao rastreador.
  def publish_alone(account)
    publish(account) if first_time?(account)
    nil
  rescue Crm::MetaAds::FacebookComments::Error => e
    e
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    nil
  end

  def new_comment?
    @value['item'] == 'comment' && @value['verb'] == 'add' && @value['comment_id'].is_a?(String) && @value['post_id'].is_a?(String)
  end

  def accounts
    Account.where(id: Crm::MetaAdsPage.account_ids_for(@page_id)).select { |account| account.feature_enabled?(FLAG) }
  end

  # A chave do dedupe só fica se o evento saiu: em qualquer outro desfecho (sem leitura, eco, erro) o `ensure` a solta.
  def publish(account)
    dispatched = false
    comment = read_comment(account)
    return if comment.nil? || comment.dig('from', 'id').to_s == @page_id

    Rails.configuration.dispatcher.dispatch(META_ADS_COMMENT_RECEIVED, Time.zone.now, payload(account, comment))
    dispatched = true
  ensure
    Redis::Alfred.delete(dedup_key(account)) unless dispatched
  end

  def read_comment(account)
    connection = Crm::MetaAdsConnection.active.find_by(account_id: account.id)
    return if connection.nil?

    Crm::MetaAds::FacebookComments.new(connection).comment(@value['post_id'], @value['comment_id'])
  end

  def dedup_key(account)
    "facebook:comment_received:#{account.id}:#{@value['comment_id']}"
  end

  def first_time?(account)
    Redis::Alfred.set(dedup_key(account), 1, nx: true, ex: DEDUP.to_i) ? true : false
  end

  def payload(account, comment)
    {
      network: NETWORK, account_id: account.id, inbox_id: inbox_id(account), page_id: @page_id,
      post_id: @value['post_id'], ad_id: nil, comment_id: @value['comment_id'], parent_id: parent_id,
      from_id: comment.dig('from', 'id')&.to_s, from_name: comment.dig('from', 'name'), text: comment['message'],
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
