# #2246: marca de "o próprio sistema acabou de mandar uma leitura nesta conversa". A leitura que o fork manda ao
# canal (ConversaCanal::LeituraNoCanal, pela Cloud ou pelo sendSeen do WAHA, e o "digitando" da Cloud em
# Conversations::ChannelTyping::Deliverer, que também marca como lida) se espalha pelos aparelhos do número e pode
# voltar ao motor como "outro aparelho meu leu". Sem esta marca, um robô respondendo apagaria a bolinha como se uma
# pessoa tivesse lido no celular (ConversaCanal::VistaNoCelular).
#
# A marca vale JANELA a partir do pedido. Leitura do celular que chega dentro dela é descartada: erra para "não lida",
# o lado seguro. Sem Redis, `recente?` responde true (descarta) e `registrar` só deixa log: a leitura ao canal segue.
module ConversaCanal::LeituraDoSistema
  JANELA = 2.minutes

  def self.registrar(conversation)
    ::Redis::Alfred.setex(chave(conversation), '1', JANELA.to_i)
  rescue Redis::BaseError => e
    Rails.logger.warn("[conversa_canal][leitura_do_sistema] marca não gravada conversation=#{conversation.id} #{e.class}")
  end

  def self.recente?(conversation)
    ::Redis::Alfred.exists?(chave(conversation))
  rescue Redis::BaseError => e
    Rails.logger.warn("[conversa_canal][leitura_do_sistema] marca não lida conversation=#{conversation.id} #{e.class}")
    true
  end

  def self.chave(conversation)
    "conversa_canal:leitura_do_sistema:#{conversation.id}"
  end
end
