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

  def privado(care)
    resultado = Crm::MetaAds::InstagramPrivateReply.new(@inbox.channel)
                                                   .perform!(comment: comment, text: care.texto_do_privado, actor: REGISTRO::ACTOR,
                                                             ad_id: @comentario.ad_id)
    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: resultado[:conversation])
  rescue Crm::MetaAds::InstagramPrivateReply::Error => e
    Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: e.code)
  end

  def ler
    resultado = cliente.comment(@comentario.comment_id)
    # Token caído ou permissão tirada também tentam de novo: um problema da caixa não descarta, um a um, os comentários
    # da conta. Só o comentário que não existe mais (ou outra recusa dele) é descartado.
    raise Crm::MetaAds::ComentariosIa::Rede::Indisponivel if resultado.transient? || resultado.token_invalid? || resultado.scope_error?
    return unless resultado.ok

    dados = resultado.data.to_h
    { text: dados['text'], from_name: dados.dig('from', 'username'), from_id: dados.dig('from', 'id')&.to_s }
  end

  def responder(texto)
    acao('reply') { cliente.reply(@comentario.comment_id, texto) }
  end

  def esconder
    acao('hide') { cliente.hide(@comentario.comment_id, hidden: true) }
  end

  private

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
