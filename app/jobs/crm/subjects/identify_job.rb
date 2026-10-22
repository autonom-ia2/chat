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
# `ordem`: a regra do turno no momento do ENQUEUE (Crm::Subjects.identificar_depois), a mesma que escolheu a fila e a
# espera. O Sync em linha segue essa decisão: uma passagem que abre ou fecha nos segundos da espera não faz o Sync ser
# pulado em silêncio. Job sem o argumento (enfileirado antes desta versão) lê a regra na hora.
#
# Marco que não grava (Redis fora, ou outros jobs gravando sem parar): a falha vai para o rastreador e o job levanta,
# para o retry gravar de novo. Com a decisão já concluída, a reserva única (Crm::SubjectDecision, conversa + mensagem)
# devolve a mesma decisão e o retry não pergunta o assunto outra vez; se a decisão quebrou antes de aplicar, a reserva
# é desfeita e o retry pergunta de novo, como antes. Enquanto isso, o ReplyJob cai no teto de 20 s (fallback explícito).
# Na exceção da decisão, o marco e o evento saem com estado 'erro' (contrato com o Agentes IA) e o retry os repete
# com o estado real.
#
# O que vem depois da decisão (o Sync em linha e a parada da cadência de follow-up no card que é o assunto, corrida f)
# roda mesmo quando a decisão quebrou no meio (o aviso em tempo real, por exemplo): o assunto pode já estar aplicado,
# e sem isso o marco sairia antes do Sync e a cadência não pararia.
#
# Com a flag `crm_avaliar_toda_mensagem` (#1675), o último passo faz a IA do CRM reler o card em foco, já o do assunto
# decidido (Crm::Conversations::CardEmFoco). Não repete o que a troca de foco ou o card novo já agendaram. Quando a
# decisão traz a lista de cards que a mensagem tocou (#1693), a IA avalia esses cards numa chamada só
# (Crm::Conversations::CardsTocados). Sem assunto ("obrigado!", "já fechei com outra") a lista traz o card em foco
# (#1918), e a IA de etapa decide se ele fica ou muda; lista vazia (sem card aberto, pedido novo que virou sugestão)
# não avalia nada.
class Crm::Subjects::IdentifyJob < ApplicationJob
  EVENTO = 'crm.subject.decided'.freeze

  queue_as :low

  def perform(conversation_id, message_id, ordem = nil)
    @estado = 'erro'
    @mais_nova = false
    @ordem = ordem
    begin
      @estado = Crm::Config.enabled? ? identificar(conversation_id, message_id) : 'crm_desligado'
    rescue StandardError
      # A exceção da decisão é a que segue para o retry; o marco sai mesmo assim, e a falha dele só vai para o log.
      marcar(conversation_id, message_id, levantar: false)
      raise
    end
    marcar(conversation_id, message_id) unless @mais_nova
  end

  private

  def identificar(conversation_id, message_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = conversation&.messages&.find_by(id: message_id)
    return 'mensagem_sumida' if message.blank?

    # Vale também para a mensagem recuperada pelo WhatsApp Híbrido (#1638): se o cliente já mandou outra depois, a
    # decisão da mais nova manda e a recuperada não é perguntada de novo.
    return mais_nova! if conversation.messages.incoming.exists?(id: (message.id + 1)..)

    decidir(conversation, message)
  end

  # IA entende a conversa F4 (flag `crm_ia_leitor_de_midia`): a espera do assunto na ordem do turno é curta, então os
  # anexos da rajada que o job da chegada ainda não leu são lidos aqui, em linha, antes da pergunta (a trava por anexo
  # faz quem chega depois esperar e encontrar lido). Sem a flag, não faz nada.
  def decidir(conversation, message)
    Crm::Ai::LeitorDeMidia.ler_a_rajada(conversation, message)
    decisao = Crm::Subjects::Identifier.new(conversation: conversation, message: message).perform
    decisao&.state || 'sem_decisao'
  ensure
    depois_da_decisao(conversation, message)
  end

  def mais_nova!
    @mais_nova = true
    'mensagem_mais_nova'
  end

  # Cada passo relê a conversa dentro do próprio cuidado: uma falha ao reler (conversa apagada no meio) não esconde a
  # exceção da decisão nem pula o outro passo.
  def depois_da_decisao(conversation, message)
    cuidar('sync') { sincronizar_dono(conversation.reload) }
    cuidar('cadencia') { parar_cadencia(conversation.reload, message) }
    cuidar('avaliacao') { avaliar_card_em_foco(conversation, message) }
  end

  def avaliar_card_em_foco(conversation, message)
    return unless Crm::Conversations::CardEmFoco.ligada?(conversation.account)

    Crm::Conversations::CardsTocados.new(conversation: conversation.reload, message: message).perform
  end

  def sincronizar_dono(conversation)
    ordem = @ordem.nil? ? Crm::Subjects.ordem_do_turno?(conversation) : @ordem
    return unless ordem

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

  def marcar(conversation_id, message_id, levantar: true)
    gravar_marco(conversation_id, message_id, levantar)
    avisar_decisao(conversation_id, message_id)
  end

  def gravar_marco(conversation_id, message_id, levantar)
    Crm::Subjects::Marco.gravar(conversation_id, message_id)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[crm][assunto] marco_nao_gravado conversa=#{conversation_id} mensagem=#{message_id} erro=#{e.class}")
    raise if levantar
  end

  # Quem assina o evento não derruba o job: o marco já foi gravado, e um retry só repetiria o aviso.
  def avisar_decisao(conversation_id, message_id)
    ActiveSupport::Notifications.instrument(EVENTO, conversation_id: conversation_id, message_id: message_id, estado: @estado)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[crm][assunto] aviso_da_decisao_falhou conversa=#{conversation_id} mensagem=#{message_id} erro=#{e.class}")
  end
end
