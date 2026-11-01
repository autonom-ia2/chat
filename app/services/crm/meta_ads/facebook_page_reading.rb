# A leitura de Crm::MetaAds::FacebookComments pelo evento do webhook, sem pessoa (IA que cuida dos comentários, #2212):
# só em post de Página da conta e com a leitura concedida, com o token da Página. nil quando não dá para ler (a recusa
# vai ao log, só com ids); Meta fora do ar (`meta_unavailable`) sobe, para quem chama tentar de novo. A Página já é da
# conta: aqui ela não é registrada de novo. Usa de quem o inclui (FacebookComments) `Error`, `READ`, `granted?`,
# `own_page?`, `page_client` e `graph!`.
module Crm::MetaAds::FacebookPageReading
  # Para quem consome `meta_ads.comment_received`, que leva só ids: o comentário como a Graph devolve (`message`,
  # `from`, `attachment`).
  def comment(post_id, comment_id)
    read_from_page(post_id, 'comentário', "comment=#{comment_id}") do
      raise self.class::Error, 'comment_not_found' unless Crm::MetaAds::FacebookCommentId.of_post?(comment_id, post_id)

      page_client(post_id)&.then { |client| graph!(client.page_comment(comment_id)) }
    end
  end

  # O texto do post, para a IA saber do que o comentário fala (#2424).
  def post_message(post_id)
    read_from_page(post_id, 'post', "post=#{post_id}") do
      page_client(post_id)&.then { |client| graph!(client.page_post_message(post_id)).to_h['message'] }
    end
  end

  private

  def read_from_page(post_id, what, ids)
    return unless granted?(self.class::READ) && own_page?(post_id)

    yield
  rescue self.class::Error => e
    raise if e.code == 'meta_unavailable'

    Rails.logger.warn("[meta_ads] #{what} do Facebook não lido: #{e.code} account=#{@connection.account_id} #{ids}")
    nil
  end
end
