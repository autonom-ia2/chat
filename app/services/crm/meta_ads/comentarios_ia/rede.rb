# IA cuida dos comentários (#2212): as três ações da IA num comentário — o privado (Private Reply: a mensagem que
# responde a um comentário, a única que a Meta deixa mandar a quem nunca escreveu), a resposta pública e o esconder.
# Cada rede tem o seu adaptador, que usa os serviços do #2196 e do #2197 sempre que eles existem:
# - Instagram (Rede::Instagram): o privado pelo Crm::MetaAds::InstagramPrivateReply, que reivindica, confere a janela
#   de 7 dias, envia e abre a conversa; a resposta e o esconder pelo Instagram::CommentsClient;
# - Facebook (Rede::Facebook): o privado pelo Messenger é nosso (Rede::Pagina, token da caixa); a resposta e o
#   esconder pelo Crm::MetaAds::FacebookComments, que grava a ação.
#
# `privado_disponivel?` diz se a rede já deixa a IA mandar o privado (o Facebook espera a pages_messaging, F4).
# Todo adaptador responde `privado(care)` com um Envio (ok, conversation, erro) e `responder(texto)` e `esconder` com
# true ou false. Nada levanta para o job: a recusa da Meta é um resultado.
#
# E `ler`: o texto e o nome de quem comentou, lidos na Meta na hora, porque o evento leva só ids (#2327). Devolve
# `{ text:, from_name: }`, ou nil quando a Meta diz que não dá para ler (comentário apagado, sem permissão, Página de
# outra conta): esse não volta. Meta fora do ar levanta Indisponivel, e o CuidarJob tenta de novo, com teto.
module Crm::MetaAds::ComentariosIa::Rede
  Envio = Struct.new(:ok, :recipient_id, :message_id, :conversation, :erro, :talvez_entregue, keyword_init: true)
  # O privado já tinha saído (pela pessoa, na tela do #2196, ou por outro job): nada a fazer, nem falha a mostrar.
  JA_FEITO = 'private_reply_done'.freeze
  # A Meta não respondeu à leitura do comentário (rede, 5xx, limite).
  class Indisponivel < StandardError; end

  module_function

  def para(inbox, comentario)
    case inbox.channel
    when Channel::Instagram then Instagram.new(inbox, comentario)
    when Channel::FacebookPage then Facebook.new(inbox, comentario)
    end
  end
end
