# IA cuida dos comentários (#2212): as ações no Instagram, com os serviços do #2196.
#
# O privado vai só com texto: o InstagramPrivateReply manda texto, e o botão do WhatsApp fica no Messenger até a chamada
# real confirmar que o Private Reply do Instagram aceita modelo (docs/comentarios-ia/DEMO.md, "A confirmar").
class Crm::MetaAds::ComentariosIa::Rede::Instagram
  REGISTRO = Crm::MetaAds::ComentariosIa::Registro

  def initialize(inbox, comentario)
    @inbox = inbox
    @comentario = comentario
  end

  def privado_disponivel?
    true
  end

  # Outro envio deste comentário (já feito, ou saindo agora em outra requisição): nada a fazer.
  OUTRO_ENVIO = %w[private_reply_done private_reply_retry].freeze

  def privado(care)
    resultado = Crm::MetaAds::InstagramPrivateReply.new(@inbox.channel)
                                                   .perform!(comment: comment, text: care.texto_do_privado, actor: REGISTRO::ACTOR,
                                                             ad_id: @comentario.ad_id)
    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: resultado[:conversation])
  rescue Crm::MetaAds::InstagramPrivateReply::Error => e
    erro = OUTRO_ENVIO.include?(e.code) ? Crm::MetaAds::ComentariosIa::Rede::JA_FEITO : e.code
    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: erro, talvez_entregue: sem_confirmacao?)
  end

  def ler
    resultado = cliente.comment(@comentario.comment_id)
    # Token caído ou permissão tirada também tentam de novo: um problema da caixa não descarta, um a um, os comentários
    # da conta. Só o comentário que não existe mais (ou outra recusa dele) é descartado.
    raise Crm::MetaAds::ComentariosIa::Rede::Indisponivel if resultado.transient? || resultado.token_invalid? || resultado.scope_error?
    return unless resultado.ok

    dados = resultado.data.to_h
    return if de_outro_post?(dados)

    { text: dados['text'], from_name: dados.dig('from', 'username'), from_id: dados.dig('from', 'id')&.to_s }
  end

  # A legenda do post (#2424), ou nil. Meta fora do ar levanta Indisponivel, como o `ler`.
  def legenda
    return if @comentario.post_id.blank?

    resultado = cliente.caption(@comentario.post_id)
    raise Crm::MetaAds::ComentariosIa::Rede::Indisponivel if resultado.transient? || resultado.token_invalid? || resultado.scope_error?

    resultado.data.to_h['caption'] if resultado.ok
  end

  def responder(texto)
    acao('reply') { cliente.reply(@comentario.comment_id, texto) }
  end

  def esconder
    acao('hide') { cliente.hide(@comentario.comment_id, hidden: true) }
  end

  private

  # O InstagramPrivateReply marca `failed_at` quando a Meta não respondeu (rede, 5xx): o privado pode ter saído.
  def sem_confirmacao?
    Crm::MetaAdsCommentAction.where(network: 'instagram', comment_id: @comentario.comment_id.to_s, action: 'private_reply', confirmed_at: nil)
                             .where.not(failed_at: nil).exists?
  end

  # Como o `of_post?` do Facebook: o comentário lido tem de ser do post do evento (o cuidado é achado pelo post).
  def de_outro_post?(dados)
    media = dados.dig('media', 'id').to_s
    media.present? && @comentario.post_id.present? && media != @comentario.post_id.to_s
  end

  # Grava depois que a Meta aceitou: a resposta e o esconder não são únicos, e o `ai_seen` já garante um job só.
  def acao(nome)
    return false unless yield.ok

    REGISTRO.gravar!(@comentario, nome)
  end

  # O comentário no formato do webhook e da Graph, que o serviço do #2196 recebe.
  def comment
    { 'id' => @comentario.comment_id, 'timestamp' => @comentario.momento&.iso8601,
      'from' => { 'id' => @comentario.from_id, 'username' => @comentario.from_name } }
  end

  def cliente
    @cliente ||= Instagram::CommentsClient.new(@inbox.channel)
  end
end
