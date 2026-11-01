# A escuta da Automação livre (#2414 F3, #2459): os gatilhos e o "esperar até" acordado pela mudança. Só confere a
# flag e chama Autonomia::Automacao::Escuta; quem decide é a Partida e o Executor.
class Autonomia::AutomacaoListener < BaseListener
  def conversation_created(event) = comecar(event, 'conversa.criada')
  def conversation_opened(event) = comecar(event, 'conversa.aberta')
  def conversation_resolved(event) = comecar(event, 'conversa.resolvida')

  def conversation_updated(event)
    conversa = event.data[:conversation]
    escuta.acordar(conversa.account, [conversa.id])
  end

  # Atividade (o histórico que a própria plataforma escreve) não é mensagem de ninguém.
  def message_created(event)
    message = event.data[:message]
    return if message.activity?

    escuta.comecar(message.conversation, 'mensagem.criada')
    escuta.acordar(message.account, [message.conversation_id])
  end

  def contact_updated(event)
    contact = event.data[:contact]
    return unless ::Autonomia::Automacao::Motor.ligado?(contact.account)

    escuta.acordar(contact.account, contact.conversations.pluck(:id))
  end

  private

  def comecar(event, tipo) = escuta.comecar(event.data[:conversation], tipo)

  def escuta = ::Autonomia::Automacao::Escuta
end
