# IA cuida dos comentários (#2212): as três ações da IA num comentário — o privado (Private Reply: a mensagem que
# responde a um comentário, a única que a Meta deixa mandar a quem nunca escreveu), a resposta pública e o esconder.
# Cada rede tem o seu adaptador, que usa os serviços do #2196 e do #2197 sempre que eles existem:
# - Instagram (Rede::Instagram): o privado pelo Crm::MetaAds::InstagramPrivateReply, que reivindica, confere a janela
#   de 7 dias, envia e abre a conversa; a resposta e o esconder pelo Instagram::CommentsClient;
# - Facebook (Rede::Facebook): o privado pelo Messenger é nosso (Rede::Pagina, token da caixa); a resposta e o
#   esconder pelo Crm::MetaAds::FacebookComments, que grava a ação.
#
# Todo adaptador responde `privado(care)` com um Envio (ok, conversation, erro) e `responder(texto)` e `esconder` com
# true ou false. Nada levanta para o job: a recusa da Meta é um resultado.
module Crm::MetaAds::ComentariosIa::Rede
  Envio = Struct.new(:ok, :recipient_id, :message_id, :conversation, :erro, keyword_init: true)
  # O privado já tinha saído (pela pessoa, na tela do #2196, ou por outro job): nada a fazer, nem falha a mostrar.
  JA_FEITO = 'private_reply_done'.freeze

  module_function

  def para(inbox, comentario)
    case inbox.channel
    when Channel::Instagram then Instagram.new(inbox, comentario)
    when Channel::FacebookPage then Facebook.new(inbox, comentario)
    end
  end
end
