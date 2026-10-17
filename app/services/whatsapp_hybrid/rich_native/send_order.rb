# Prepend em WhatsappHybrid::WebTransport (chat#1709, demo integrada): a ordem de entrega por conversa no plano B do
# Híbrido. Causa raiz da troca vista na demo (lista mandada antes da localização chegou ao motor depois dela): cada
# mensagem sai num SendReplyJob próprio, os jobs rodam em paralelo, e o "digitando…" (WhatsappHybrid::Typing) dorme um
# tempo proporcional ao texto antes do pedido. A lista, mais longa, digitava mais e saía depois da localização. Não é
# o envio nativo em si (mesmo job, mesma fila, sem espera de capacidade): a corrida é a mesma para texto, e a mensagem
# rica só a deixou visível.
# Com a flag `whatsapp_rich_native`, o envio de uma mensagem espera a vez: (1) até as mensagens mais antigas da conversa
# que ainda não começaram a sair (sem `source_id`, não falhadas, recentes) começarem; (2) uma trava por conversa no
# Redis durante o envio inteiro (digitando e pedido). As duas esperas têm teto (MAX_WAIT), para uma mensagem antiga que
# nunca sai (fila de limite, job perdido) não prender as outras para sempre. Sem a flag, como antes.
module WhatsappHybrid::RichNative::SendOrder
  LOCK_TTL = 60
  MAX_WAIT = 45
  POLL = 0.5
  ORDER_WINDOW = 2.minutes
  SENDABLE_TYPES = %w[outgoing template].freeze

  def perform
    return super unless Waha::RichNative.enabled?(@message.account)

    WhatsappHybrid::RichNative::SendOrder.in_turn(@message) { super }
  end

  def self.in_turn(message)
    deadline = monotonic + MAX_WAIT
    wait_while(deadline) { older_pending?(message) }
    token = SecureRandom.hex(8)
    key = lock_key(message)
    wait_while(deadline) { !::Redis::Alfred.set(key, token, nx: true, ex: LOCK_TTL) }
    yield
  ensure
    ::Redis::Alfred.delete(key) if key && ::Redis::Alfred.get(key) == token
  end

  # Mensagem nossa, mais antiga, da mesma conversa, que ainda não começou a sair.
  def self.older_pending?(message)
    message.conversation.messages.where(message_type: SENDABLE_TYPES, private: false, source_id: nil)
           .where(id: ...message.id).where(created_at: ORDER_WINDOW.ago..).where.not(status: :failed).exists?
  end

  def self.wait_while(deadline)
    Kernel.sleep(POLL) while yield && monotonic < deadline
  end

  def self.lock_key(message)
    "whatsapp_hybrid:send_order:#{message.conversation_id}"
  end

  def self.monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
