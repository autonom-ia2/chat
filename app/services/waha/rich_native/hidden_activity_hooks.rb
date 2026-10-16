# Prepend em HookListener (chat#1709, fase 3): a atividade escondida (`c2y_hidden`, Waha::RichNative::Inbound.hide!)
# não vai às integrações da conta (Slack, Dialogflow, Linear, Google Tradutor). No Slack ela viraria uma linha solta
# ("Reação registrada na mensagem") na thread da conversa. A atualização da mensagem a que ela se refere (o texto
# editado, a reação) segue pelo `message_updated` de sempre.
module Waha::RichNative::HiddenActivityHooks
  def message_created(event)
    return if Waha::RichNative::Inbound.hidden?(event.data[:message])

    super
  end
end
