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

  # G10 (F8.7): a etiqueta posta ou tirada começa o gatilho dela, depois de acordar quem espera.
  def conversation_updated(event)
    conversa = event.data[:conversation]
    escuta.acordar(conversa, [conversa.id])
    etiqueta.comecar(conversa, event.data[:changed_attributes], event.timestamp)
  end

  # F8.3: mudou quem atende a conversa, a pessoa ou o time.
  def assignee_changed(event) = troca(event, ::Autonomia::Automacao::TrocaNaConversa::RESPONSAVEL)
  def team_changed(event) = troca(event, ::Autonomia::Automacao::TrocaNaConversa::TIME)

  # A pessoa que a agente de IA cobria escreveu (Cobertura, decisão 18): a conversa volta para ela antes de acordar
  # quem espera, e o "a pessoa respondeu" já a vê no nome.
  def message_created(event)
    cobertura.pessoa_escreveu(event.data[:message])
    escuta.mensagem_criada(event.data[:message])
    falhou.criada(event.data[:message])
  end

  # A situação do envio que a automação mandou acorda a espera (G34), e a recusa do canal começa o gatilho (G8).
  def message_updated(event)
    escuta.envio_atualizado(event.data[:message], event.data[:previous_changes])
    falhou.atualizada(event.data[:message], event.data[:previous_changes])
  end

  def contact_updated(event)
    contact = event.data[:contact]
    escuta.acordar(contact, Conversation.where(contact_id: contact.id).select(:id))
    etiqueta.comecar(contact, event.data[:changed_attributes], event.timestamp)
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
  def crm_meeting_outcome_recorded(event) = escuta.enfileirar_evento_do_card(event.data, Events::Types::CRM_MEETING_OUTCOME_RECORDED)

  private

  # O instante do despacho, em µs, é a marca do evento (Gatilhos): o EventDispatcherJob repete o mesmo valor.
  def comecar(event, tipo)
    conversa = event.data[:conversation]
    marca = conversa && ::Autonomia::Automacao::Gatilhos.marca_do_despacho(tipo, conversa, event.timestamp)
    escuta.comecar(conversa, tipo, evento: marca)
  end

  def troca(event, tipo)
    ::Autonomia::Automacao::TrocaNaConversa.comecar(event.data[:conversation], tipo, event.data[:changed_attributes], event.timestamp)
  end

  def escuta = ::Autonomia::Automacao::Escuta
  def etiqueta = ::Autonomia::Automacao::EtiquetaMudou
  def falhou = ::Autonomia::Automacao::MensagemQueFalhou
  def cobertura = ::Autonomia::Automacao::Cobertura
end
