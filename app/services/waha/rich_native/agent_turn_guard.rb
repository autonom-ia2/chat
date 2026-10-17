# Prepend em Autonomia::Agents::Operate::Responder (chat#1709, aprovado pelo Rodrigo em 16/10/2026): o que o agente de
# IA não responde nem lê como atual, do que o recebimento grava. Só na caixa WAHA comum com a flag
# `whatsapp_rich_native`; noutra caixa, ou sem a flag, tudo como na main (exceto o voto, abaixo).
# - O turno (as mensagens do cliente depois da última resposta) é calado só quando TODAS são o que não há como
#   responder: a bolha "abra no celular" (`is_unsupported`), o aviso de visualização única (`view_once_unavailable`) ou
#   apagada pelo cliente (`deleted_by_contact_at`). Com uma mensagem real no meio, a IA responde, e o histórico sai
#   sem as outras. Evento no painel de Desempenho, uma vez por mensagem: `skipped_mensagem_sem_suporte` (com bolha ou
#   aviso no turno) ou `skipped_mensagem_apagada` (só apagadas).
# - Voto na enquete e resposta ao convite (Waha::RichNative::AiTurn, também no plano B do Híbrido), com a flag: no settle,
#   a escolha precisa continuar guardada na enquete/evento. A que não vale mais (retirada ou trocada dentro do debounce)
#   sai do turno e do histórico; se não sobrar mensagem no turno, a IA fica calada, com o evento
#   `skipped_escolha_retirada`.
# O turno calado de propósito NÃO solta a posse do turno (Autonomia::Agents::Operate::PosseDoTurno: só turno que falhou
# solta). Só depois da elegibilidade de sempre: turno que deixou de ser da IA segue o caminho original (sem evento).
module Waha::RichNative::AgentTurnGuard
  UNSUPPORTED_REASON = 'mensagem_sem_suporte'.freeze
  DELETED_REASON = 'mensagem_apagada'.freeze
  STALE_CHOICE_REASON = 'escolha_retirada'.freeze

  def perform
    reason = c2y_turn_skip_reason
    return super if reason.nil? || !still_eligible?

    c2y_skip_turn!(reason)
  end

  private

  # O mesmo memo do original: a primeira chamada pega a janela dele (guardada crua para o guard) e, na caixa WAHA com a
  # flag, guarda o histórico já sem a apagada e sem o aviso de visualização única.
  def recent_messages
    return @recent_messages if @c2y_filtered

    raw = super
    @c2y_raw_messages = raw
    @c2y_filtered = true
    @recent_messages = raw.reject { |message| c2y_out_of_history?(message) }
  end

  # Com a flag: a escolha que não vale mais (qualquer caixa) e, na caixa WAHA, a apagada e o aviso de visualização única.
  def c2y_out_of_history?(message)
    return false unless c2y_flag?

    c2y_stale_choice?(message) || (c2y_waha_with_flag? && Waha::RichNative::TurnKinds.out_of_history?(message))
  end

  # A pergunta da IA sai da última mensagem do cliente que é turno de verdade: na caixa WAHA com a flag, a bolha "abra no
  # celular", o aviso de visualização única e a apagada (Waha::RichNative::TurnKinds.kind) não são a pergunta, mesmo
  # quando chegaram por último na rajada.
  def last_incoming_message
    return super unless c2y_waha_with_flag?

    recent_messages.reverse.find { |message| message.incoming? && Waha::RichNative::TurnKinds.kind(message).nil? }
  end

  def c2y_stale_choice?(message)
    @c2y_stale ||= {}
    @c2y_stale.fetch(message.id) { @c2y_stale[message.id] = !Waha::RichNative::TurnKinds.choice_current?(message) }
  end

  def c2y_turn_skip_reason
    return unless c2y_flag?

    Waha::RichNative::TurnKinds.turn_silence(c2y_turn_incoming, waha: c2y_waha_with_flag?)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] c2y_turn_guard_failed conv=#{@conversation.id} #{e.class}")
    nil
  end

  def c2y_turn_message
    return @c2y_turn_message if defined?(@c2y_turn_message)

    @c2y_turn_message = @reply_to_message_id.present? ? @conversation.messages.find_by(id: @reply_to_message_id) : nil
  end

  # As mensagens do cliente do turno, da janela crua (antes do filtro do histórico).
  def c2y_turn_incoming
    recent_messages
    messages = Array(@c2y_raw_messages)
    last_reply = messages.rindex { |message| !message.incoming? }
    window = last_reply ? messages[(last_reply + 1)..] : messages
    Array(window).select(&:incoming?)
  end

  def c2y_flag?
    return @c2y_flag if defined?(@c2y_flag)

    @c2y_flag = Waha::RichNative.enabled?(@conversation.account)
  end

  def c2y_waha_with_flag?
    return @c2y_waha_with_flag if defined?(@c2y_waha_with_flag)

    inbox = @conversation.inbox
    @c2y_waha_with_flag = inbox&.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) == true && c2y_flag?
  end

  def c2y_skip_turn!(reason)
    registrar_silencio(reason)
    c2y_log_event(reason)
    self.class::Result.silenced
  end

  # Uma vez por mensagem do cliente (sem índice único: uma duplicata rara na corrida é aceita, como no #1669). O
  # EventLogger nunca levanta.
  def c2y_log_event(reason)
    message_id = c2y_turn_message&.id || @reply_to_message_id
    event_type = :"skipped_#{reason}"
    return if @agent.events.exists?(event_type: event_type, conversation_id: @conversation.id, message_id: message_id)

    ::Autonomia::Agents::Operate::EventLogger.create!(agent: @agent, conversation: @conversation, event_type: event_type,
                                                      message_id: message_id, handoff_reason: reason)
  end
end
