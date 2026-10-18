# Grava uma mudança da pele (#1702) numa mensagem que JÁ existe: reação, lida, áudio ouvido, apagada/editada pelo
# cliente, prévia de link. Sem as validações do Message: a anti-enxurrada (Message#prevent_message_flooding) conta
# mensagens CRIADAS no último minuto e roda em todo save; numa conversa movimentada ela recusaria a reação que já
# saiu para o WhatsApp, e a tela receberia erro. Quem chama segura a mensagem com `with_lock` e só muda chaves
# próprias. Os callbacks (message_updated, ActionCable) continuam.
module ConversaCanal::GravarNaMensagem
  module_function

  def atualizar!(message, **mudancas)
    message.assign_attributes(mudancas)
    message.save!(validate: false)
  end
end
