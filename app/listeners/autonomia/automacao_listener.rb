# A escuta da Automação livre (#2414 F3, #2459): os gatilhos e o "esperar até" acordado pela mudança. Só tira o
# registro do evento e chama Autonomia::Automacao::Escuta, que confere a flag e não deixa erro subir para o evento;
# quem decide é a Partida e o Executor.
#
# Fica no despacho assíncrono (AsyncDispatcher), nunca no síncrono, e a Partida só enfileira a rodada (perform_later),
# nunca a roda com perform_now: a ação da rodada passa pelo caderno do Guia, que é um só por thread, e uma rodada
# dentro do pedido ou do job de quem mudou a conversa quebraria com "o caderno do Guia já está aberto". O spec
# "a rodada nunca roda na thread do evento" falha se isso mudar.
class Autonomia::AutomacaoListener < BaseListener
  def conversation_created(event) = comecar(event, 'conversa.criada')
  def conversation_opened(event) = comecar(event, 'conversa.aberta')
  def conversation_resolved(event) = comecar(event, 'conversa.resolvida')

  def conversation_updated(event)
    conversa = event.data[:conversation]
    escuta.acordar(conversa, [conversa.id])
  end

  def message_created(event) = escuta.mensagem_criada(event.data[:message])
  def message_updated(event) = escuta.envio_atualizado(event.data[:message], event.data[:previous_changes])

  def contact_updated(event)
    contact = event.data[:contact]
    escuta.acordar(contact, Conversation.where(contact_id: contact.id).select(:id))
  end

  # Os eventos do card (#2499, F6): o emissor do CRM manda só ids. O listener só enfileira o EventoDoCardJob, que relê
  # o card: um erro lá tenta de novo sem repetir os webhooks e os avisos dos outros listeners deste evento.
  def crm_card_created(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_CARD_CREATED)
  def crm_card_moved(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_CARD_MOVED)
  def crm_card_won(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_CARD_WON)
  def crm_card_lost(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_CARD_LOST)

  # A reunião do card (G12) chega pelo mesmo caminho: a atividade da reunião é do card, e o evento traz só ids.
  def crm_meeting_scheduled(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_MEETING_SCHEDULED)
  def crm_meeting_rescheduled(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_MEETING_RESCHEDULED)
  def crm_meeting_canceled(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_MEETING_CANCELED)

  private

  # O instante do despacho, em µs, é a marca do evento (Gatilhos): o EventDispatcherJob repete o mesmo valor.
  def comecar(event, tipo)
    conversa = event.data[:conversation]
    marca = conversa && ::Autonomia::Automacao::Gatilhos.marca_do_despacho(tipo, conversa, event.timestamp)
    escuta.comecar(conversa, tipo, evento: marca)
  end

  def escuta = ::Autonomia::Automacao::Escuta
end
