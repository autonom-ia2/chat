# Prepend em Message (chat#1709, fase 3): a atividade escondida (`c2y_hidden`: reação, edição, desfecho de ligação e
# voto retirado, Waha::RichNative::Inbound.hide!) não mexe na conversa. Ela é só o registro de que o evento chegou; a
# mudança está na mensagem a que se refere. Sem isto, cada reação do cliente subiria a conversa na lista
# (`last_activity_at`). O resto do pós-criação segue igual (a tela recebe a atividade, que o painel não mostra).
module Waha::RichNative::HiddenActivity
  private

  def set_conversation_activity
    return if Waha::RichNative::Inbound.hidden?(self)

    super
  end
end
