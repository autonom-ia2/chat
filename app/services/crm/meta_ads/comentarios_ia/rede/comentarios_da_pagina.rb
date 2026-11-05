# IA cuida dos comentários no Facebook (#2587): ler, responder e esconder com o token da caixa da Página
# (Channel::FacebookPage), sem a conexão de Anúncios. Vale para o post da Página e para o post por trás de um anúncio:
# os dois são posts da mesma Página, e a caixa é a que o webhook achou (Crm::MetaAds::FacebookFeed#inbox_id). É o mesmo
# token do privado (Rede::Pagina) e do Seus posts (SeusPosts::ComentariosPagina). Antes, o motor lia pela conexão de
# Anúncios da conta (Crm::MetaAds::FacebookComments), e sem ela o comentário era descartado em silêncio.
#
# A interface é a que o Rede::Facebook usava: `comment`, `post_message`, `post_media`, `reply_as_ai` e `hide_as_ai`.
# Só age em post desta Página e em comentário desse post (Crm::MetaAds::FacebookCommentId); o resto é
# `comment_not_found` (ou nil na leitura do post), sem chamar a Meta. Erros, com os códigos do FacebookComments:
# `meta_unavailable` (rede, 5xx, limite), `needs_login` (o token da caixa sem pages_read_user_content ou
# pages_manage_engagement, ou caído: o "Libere o acesso" do Seus posts resolve), `invalid_text` e `meta_refused`.
# Cada resposta e cada esconder ficam em crm_meta_ads_comment_actions como 'ai', sem anúncio e sem o texto.
class Crm::MetaAds::ComentariosIa::Rede::ComentariosDaPagina
  Error = Crm::MetaAds::FacebookComments::Error
  NETWORK = Crm::MetaAds::FacebookComments::NETWORK

  # prazo: o relógio monotônico até o qual quem chama espera (Meta::AdsGraphClient::Prazo), como no FacebookComments.
  def initialize(canal, prazo: nil)
    @canal = canal
    @prazo = prazo
  end

  def comment(post_id, comment_id)
    do_post!(post_id, comment_id)
    graph!(client.page_comment(comment_id))
  end

  def post_message(post_id)
    graph!(client.page_post_message(post_id))['message'] if desta_pagina?(post_id)
  end

  def post_media(post_id)
    graph!(client.page_post_media(post_id)) if desta_pagina?(post_id)
  end

  def reply_as_ai(post_id, comment_id, message)
    text = message.to_s.strip
    raise Error, 'invalid_text' if text.empty? || text.length > Crm::MetaAds::FacebookComments::MESSAGE_MAX

    { id: agir!(post_id, comment_id, 'reply') { client.reply_comment(comment_id, text) }['id'] }
  end

  def hide_as_ai(post_id, comment_id, hidden)
    agir!(post_id, comment_id, hidden ? 'hide' : 'show') { client.hide_comment(comment_id, hidden) }
    hidden
  end

  private

  def desta_pagina?(post_id)
    post_id.to_s.split('_').first == @canal.page_id.to_s
  end

  def do_post!(post_id, comment_id)
    return if desta_pagina?(post_id) && Crm::MetaAds::FacebookCommentId.of_post?(comment_id.to_s, post_id.to_s)

    raise Error, 'comment_not_found'
  end

  def agir!(post_id, comment_id, acao)
    do_post!(post_id, comment_id)
    data = graph!(yield)
    gravar(acao, comment_id)
    data
  end

  # A Meta já agiu quando isto roda: falha ao gravar vai ao rastreador, e a resposta continua dizendo a verdade.
  def gravar(acao, comment_id)
    Crm::MetaAdsCommentAction.record!(account: @canal.account, network: NETWORK, ad_id: nil, comment_id: comment_id.to_s,
                                      action: acao, actor: 'ai', user: nil)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @canal.account).capture_exception
  end

  def graph!(result)
    return result.data.to_h if result.ok
    raise Error, 'needs_login' if result.scope_error? || result.token_invalid?

    raise Error, result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @canal.page_access_token, prazo: @prazo).extend(Meta::AdsGraphClient::PageComments)
  end
end
