# #2246: marca de "o próprio sistema já marcou como lidas, no canal, as mensagens desta conversa até aqui". A leitura
# que o fork manda ao canal (ConversaCanal::LeituraNoCanal, pela Cloud ou pelo sendSeen do WAHA, e o "digitando" da
# Cloud em Conversations::ChannelTyping::Deliverer, que também marca como lida) se espalha pelos aparelhos do número e
# pode voltar ao motor como "outro aparelho meu leu". Sem esta marca, um robô respondendo apagaria a bolinha como se
# uma pessoa tivesse lido no celular (ConversaCanal::VistaNoCelular).
#
# A marca guarda ATÉ ONDE o sistema marcou: o created_at da mensagem marcada (a Meta marca a última e as anteriores; o
# sendSeen do WAHA marca o chat inteiro). Leitura do celular de mensagem coberta pela marca é descartada; a de mensagem
# que chegou DEPOIS conta. Por isso:
# - o atraso da fila não importa: a comparação é entre a mensagem lida e a marca, as duas no relógio do servidor, e não
#   entre a hora em que o job roda e a hora do pedido;
# - o robô que "digita" a cada pedaço da resposta não come a leitura de quem abre a conversa no celular depois: a
#   leitura de mensagem que chegou depois da última marca do robô passa;
# - perder uma leitura coberta não custa nada: o celular não manda leitura de mensagem que já está lida. Só se perde
#   quando a marcação do sistema falhou no canal, e aí erra para "não lida", o lado seguro.
# A marca só anda para a frente (WATCH/MULTI, como Crm::Subjects::Marco) e dura MEMORIA, bem mais que qualquer atraso
# de fila. Só é gravada com a flag `leitura_no_celular` da conta: desligada, nada muda na leitura ao canal nem no
# "digitando" (nem uma ida ao Redis a mais). Sem Redis, `cobre?` responde true (descarta) e `registrar` só deixa log:
# a falha da marca nunca impede a leitura ao canal nem o "digitando".
module ConversaCanal::LeituraDoSistema
  MEMORIA = 1.day
  TENTATIVAS = 5
  MICROSSEGUNDOS = 1_000_000

  def self.registrar(conversation, ate:)
    return unless ConversaCanal::VistaNoCelular.enabled?(conversation.account)

    chave = chave(conversation)
    valor = (ate.to_r * MICROSSEGUNDOS).to_i
    gravado = ::Redis::Alfred.with do |conn|
      TENTATIVAS.times.any? do
        conn.watch(chave) do
          novo = [conn.get(chave).to_i, valor].max
          conn.multi { |transacao| transacao.set(chave, novo, ex: MEMORIA.to_i) }
        end
      end
    end
    Rails.logger.warn("[conversa_canal][leitura_do_sistema] marca não gravada conversation=#{conversation.id} concorrência") unless gravado
  rescue StandardError => e
    Rails.logger.warn("[conversa_canal][leitura_do_sistema] marca não gravada conversation=#{conversation.id} #{e.class}")
  end

  # A mensagem já tinha sido marcada como lida pelo próprio sistema?
  def self.cobre?(mensagem)
    marca = ate(mensagem.conversation)
    marca.present? && mensagem.created_at <= marca
  rescue Redis::BaseError => e
    Rails.logger.warn("[conversa_canal][leitura_do_sistema] marca não lida conversation=#{mensagem.conversation_id} #{e.class}")
    true
  end

  def self.ate(conversation)
    valor = ::Redis::Alfred.get(chave(conversation))
    Time.zone.at(Rational(valor.to_i, MICROSSEGUNDOS)) if valor.present?
  end

  def self.chave(conversation)
    "conversa_canal:lida_pelo_sistema:#{conversation.id}"
  end
end
