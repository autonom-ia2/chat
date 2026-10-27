# IA cuida dos comentários (#2212): as ações na Página do Facebook.
# - privado pelo Messenger: nosso (Rede::Pagina, com o token da caixa). Reivindica antes, abre a conversa na caixa do
#   Messenger com a mensagem que saiu (Conversa.no_messenger!); recusado, a linha sai;
# - resposta e esconder: Crm::MetaAds::FacebookComments do #2197, com a conexão de anúncios da conta. Ele confere que o
#   comentário é do post e que a Página é da conta, e grava a ação com actor 'ai'.
class Crm::MetaAds::ComentariosIa::Rede::Facebook
  REGISTRO = Crm::MetaAds::ComentariosIa::Registro

  def initialize(inbox, comentario)
    @inbox = inbox
    @comentario = comentario
  end

  def privado(care)
    return Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: Crm::MetaAds::ComentariosIa::Rede::JA_FEITO) unless reivindicou?

    envio = Crm::MetaAds::ComentariosIa::Rede::Pagina.new(@inbox.channel).private_reply(@comentario.comment_id, mensagem(care))
    return soltar(envio) unless envio.ok

    envio.conversation = na_caixa(envio, care)
    envio
  end

  def responder(texto)
    comentarios&.reply_on_post!(@comentario.post_id, @comentario.comment_id, texto, actor: REGISTRO::ACTOR).present?
  rescue Crm::MetaAds::FacebookComments::Error
    false
  end

  def esconder
    comentarios&.hide_on_post!(@comentario.post_id, @comentario.comment_id, true, actor: REGISTRO::ACTOR) == true
  rescue Crm::MetaAds::FacebookComments::Error
    false
  end

  private

  # O privado já saiu: uma falha ao abrir a conversa não pode soltar a reivindicação (o reenvio mandaria de novo).
  def na_caixa(envio, care)
    Crm::MetaAds::ComentariosIa::Conversa.no_messenger!(@comentario, envio, care.message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception
    nil
  end

  def reivindicou?
    REGISTRO.reivindicar!(@comentario, 'private_reply')
  end

  def soltar(envio)
    REGISTRO.soltar!(@comentario, 'private_reply')
    envio
  end

  def mensagem(care)
    button = care.button
    return { text: care.message } if button.blank?

    { attachment: { type: 'template', payload: { template_type: 'button', text: care.message,
                                                 buttons: [{ type: 'web_url', url: button['url'], title: button['title'] }] } } }
  end

  def comentarios
    conexao = Crm::MetaAdsConnection.find_by(account_id: @comentario.account_id)
    conexao && Crm::MetaAds::FacebookComments.new(conexao)
  end
end
