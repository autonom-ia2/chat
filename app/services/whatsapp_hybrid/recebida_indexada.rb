# Prepend em Whatsapp::IncomingMessageBaseService (#2246): na caixa híbrida, a mensagem do cliente que chega pela Cloud
# tem o id físico guardado, para a leitura feita no celular encontrá-la (WhatsappHybrid::LeituraNoCelular). Falhar
# aqui nunca derruba a chegada da mensagem: vira log, e a leitura dela no celular só não apaga a bolinha.
module WhatsappHybrid::RecebidaIndexada
  private

  def process_messages
    resultado = super
    indexar_recebida
    resultado
  end

  def indexar_recebida
    WhatsappHybrid::LeituraNoCelular.indexar(@message)
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.warn("[whatsapp_hybrid][leitura_no_celular] índice não gravado message=#{@message&.id} #{e.class}")
  end
end
