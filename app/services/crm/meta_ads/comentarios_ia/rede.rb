# IA cuida dos comentários (#2212): as três ações da IA no comentário, iguais nas duas redes — o privado (Private
# Reply: a mensagem que responde a um comentário, a única que a Meta deixa mandar a quem nunca escreveu), a resposta
# pública e o esconder. Cada rede tem o seu cliente, com o token da caixa:
# - Instagram: Instagram::CommentsClient (#2196), na graph.instagram.com;
# - Facebook: Crm::MetaAds::ComentariosIa::Rede::Pagina, na graph.facebook.com com o token da Página (pages_messaging).
#
# O botão "Chamar no WhatsApp" vai como modelo de botão. A Meta não diz se o Private Reply aceita modelo: se recusar, o
# privado conta como falha e aparece em "Para você ver" (a confirmar na chamada real, docs/comentarios-ia/DEMO.md).
class Crm::MetaAds::ComentariosIa::Rede
  Envio = Struct.new(:ok, :recipient_id, :message_id, :erro, keyword_init: true)

  def self.para(inbox)
    cliente = case inbox.channel
              when Channel::Instagram then Instagram::CommentsClient.new(inbox.channel)
              when Channel::FacebookPage then Pagina.new(inbox.channel)
              end
    cliente && new(cliente)
  end

  def initialize(cliente)
    @cliente = cliente
  end

  def private_reply(comment_id, texto, button:)
    @cliente.private_reply(comment_id, mensagem(texto, button))
  end

  def reply(comment_id, texto)
    @cliente.reply(comment_id, texto)
  end

  def hide(comment_id)
    @cliente.hide(comment_id)
  end

  private

  def mensagem(texto, button)
    return { text: texto } if button.blank?

    { attachment: { type: 'template', payload: { template_type: 'button', text: texto,
                                                 buttons: [{ type: 'web_url', url: button['url'], title: button['title'] }] } } }
  end
end
