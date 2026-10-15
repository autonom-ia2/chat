# Multifunil 5/11 (#1145): pergunta o assunto da mensagem recebida, depois da espera (Crm::Subjects::DEBOUNCE). Se o
# cliente mandou outra mensagem nesse meio-tempo, quem pergunta é o job dela: uma rajada vira uma pergunta só.
#
# Um turno, uma ordem (#1606): assunto → quem responde → resposta. Na ordem do turno (Crm::Subjects.ordem_do_turno?),
# depois de decidir o assunto o job troca o dono EM LINHA (ResponsibleAgentSync, sob a trava da conversa), e só então
# grava o marco (Crm::Subjects::Marco) que o ReplyJob do Agentes IA espera. TODA saída grava o marco e emite
# EVENTO ({ conversation_id:, message_id:, estado: }), inclusive o CRM desligado, a mensagem sumida e a exceção
# (contrato aceito com o Agentes IA: sem marco, o turno esperaria até o teto de 20 s); a única que não grava é a da
# mensagem mais nova, porque o marco daquela rajada vem do job dela. A exceção segue para o retry do job, que decide de
# novo e regrava o marco (o marco só avança).
#
# O que vem depois da decisão (o Sync em linha e a parada da cadência de follow-up no card que é o assunto, corrida f)
# roda mesmo quando a decisão quebrou no meio (o aviso em tempo real, por exemplo): o assunto pode já estar aplicado,
# e sem isso o marco sairia antes do Sync e a cadência não pararia.
class Crm::Subjects::IdentifyJob < ApplicationJob
  EVENTO = 'crm.subject.decided'.freeze

  queue_as :low

  def perform(conversation_id, message_id)
    @estado = 'erro'
    @mais_nova = false
    return @estado = 'crm_desligado' unless Crm::Config.enabled?

    @estado = identificar(conversation_id, message_id)
  ensure
    marcar(conversation_id, message_id) unless @mais_nova
  end

  private

  def identificar(conversation_id, message_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = conversation&.messages&.find_by(id: message_id)
    return 'mensagem_sumida' if message.blank?
    return mais_nova! if conversation.messages.incoming.exists?(id: (message.id + 1)..)

    decidir(conversation, message)
  end

  def decidir(conversation, message)
    decisao = Crm::Subjects::Identifier.new(conversation: conversation, message: message).perform
    decisao&.state || 'sem_decisao'
  ensure
    depois_da_decisao(conversation.reload, message)
  end

  def mais_nova!
    @mais_nova = true
    'mensagem_mais_nova'
  end

  def depois_da_decisao(conversation, message)
    cuidar('sync') { sincronizar_dono(conversation) }
    cuidar('cadencia') { parar_cadencia(conversation, message) }
  end

  def sincronizar_dono(conversation)
    return unless Crm::Subjects.ordem_do_turno?(conversation)

    Crm::Ai::ResponsibleAgentSync.new(conversation: conversation, motivo: Crm::Ai::ResponsibleAgentSync::FOCO).perform
  end

  def parar_cadencia(conversation, message)
    card = Crm::Assunto.funil_atual(conversation)
    Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: message).maybe_cancel if card
  end

  # Cada passo depois da decisão é independente: uma falha num não impede o outro nem o marco, e não esconde a exceção
  # da decisão. Vai para o rastreador de erros e para o log, só com ids.
  def cuidar(passo)
    yield
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[crm][assunto] depois_da_decisao_falhou passo=#{passo} erro=#{e.class}")
  end

  def marcar(conversation_id, message_id)
    Crm::Subjects::Marco.gravar(conversation_id, message_id)
    ActiveSupport::Notifications.instrument(EVENTO, conversation_id: conversation_id, message_id: message_id, estado: @estado)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[crm][assunto] marco_nao_gravado conversa=#{conversation_id} mensagem=#{message_id} erro=#{e.class}")
  end
end
