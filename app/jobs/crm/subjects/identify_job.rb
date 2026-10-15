# Multifunil 5/11 (#1145): pergunta o assunto da mensagem recebida, depois da espera (Crm::Subjects::DEBOUNCE). Se o
# cliente mandou outra mensagem nesse meio-tempo, quem pergunta é o job dela: uma rajada vira uma pergunta só.
#
# Um turno, uma ordem (#1606): assunto → quem responde → resposta. Na ordem do turno (Crm::Subjects.ordem_do_turno?),
# depois de decidir o assunto o job troca o dono EM LINHA (ResponsibleAgentSync, sob a trava da conversa), e só então
# grava o marco (Crm::Subjects::Marco) que o ReplyJob do Agentes IA espera. TODA saída grava o marco e emite
# EVENTO ({ conversation_id:, message_id:, estado: }), inclusive o CRM desligado, a mensagem sumida e a exceção; a única
# que não grava é a da mensagem mais nova, porque o marco daquela rajada vem do job dela.
#
# Também na ordem do assunto: a resposta do cliente para a cadência de follow-up do card que é o assunto DEPOIS da
# decisão (corrida f), e não do card que estava em foco quando a mensagem chegou.
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

    decisao = Crm::Subjects::Identifier.new(conversation: conversation, message: message).perform
    depois_da_decisao(conversation.reload, message)
    decisao&.state || 'sem_decisao'
  end

  def mais_nova!
    @mais_nova = true
    'mensagem_mais_nova'
  end

  def depois_da_decisao(conversation, message)
    if Crm::Subjects.ordem_do_turno?(conversation)
      Crm::Ai::ResponsibleAgentSync.new(conversation: conversation, motivo: Crm::Ai::ResponsibleAgentSync::FOCO).perform
    end
    card = Crm::Assunto.funil_atual(conversation)
    Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: message).maybe_cancel if card
  end

  # Sem Redis o marco não sai: o ReplyJob responde no teto de 20 s com o dono atual. A falha fica no log e não esconde
  # a exceção original do job.
  def marcar(conversation_id, message_id)
    Crm::Subjects::Marco.gravar(conversation_id, message_id)
    ActiveSupport::Notifications.instrument(EVENTO, conversation_id: conversation_id, message_id: message_id, estado: @estado)
  rescue Redis::BaseError => e
    Rails.logger.error("[crm][assunto] marco_nao_gravado conversa=#{conversation_id} mensagem=#{message_id} erro=#{e.class}")
  end
end
