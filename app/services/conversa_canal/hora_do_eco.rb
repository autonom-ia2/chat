# Prepend em Whatsapp::IncomingMessageBaseService (#2202, PR 0). O eco do que a equipe mandou pelo celular (Cloud com
# coexistência e caixa híbrida, que recebe pela Cloud) chega com a hora em que o WhatsApp o enviou, no `timestamp` da
# mensagem do webhook (segundos). A mensagem aqui nasce com a hora da CHEGADA, que pode vir minutos depois. Guarda a
# hora do envio em `external_created_at` (a chave que o Chatwoot já tem para "criada fora em outra hora", Message
# store), para o "visto" da conversa ir só até o envio (ConversaCanal::VistaAoResponder.antes_do_envio).
# Só no eco; a hora vale só quando é uma hora plausível (Waha::RichNative::EventTime.at).
module ConversaCanal::HoraDoEco
  CHAVE = 'external_created_at'.freeze

  private

  def message_content_attributes(message)
    attrs = super
    return attrs unless outgoing_echo

    enviada = ::Waha::RichNative::EventTime.at(message[:timestamp])
    enviada ? attrs.merge(CHAVE => enviada.to_i) : attrs
  end
end
