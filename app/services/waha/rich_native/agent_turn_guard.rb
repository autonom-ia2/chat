# Prepend em Autonomia::Agents::Operate::Responder (chat#1709, aprovado pelo Rodrigo em 16/10/2026): o que o agente de
# IA não responde nem lê como atual, do que o recebimento grava. Só na caixa WAHA comum com a flag
# `whatsapp_rich_native`; noutra caixa, ou sem a flag, tudo como na main (exceto o voto, abaixo, e a apagada pelo
# cliente, que vale em qualquer caixa em que a mensagem tenha `deleted_by_contact_at`: sai do histórico e o turno só de
# apagadas cala com `skipped_mensagem_apagada`).
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
  # As marcas (verdadeiras) das mensagens do cliente que não contam como interação na janela do histórico: o voto
  # escondido (só recebido: o filtro já é `incoming`), a bolha e o aviso de visualização única; a apagada vai à parte
  # (chave presente).
  UNCOUNTED_FLAGS = %w[c2y_hidden is_unsupported view_once_unavailable].freeze

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

  # A apagada pelo cliente (`deleted_by_contact_at`), em QUALQUER caixa: a chave só existe quando algo a gravou (o
  # #1702b na Cloud e no híbrido, o conector na WAHA), e quem não ligou nada fica como na main. Com a flag: a escolha
  # que não vale mais (qualquer caixa) e, na caixa WAHA, o aviso de visualização única.
  def c2y_out_of_history?(message)
    return true if Waha::RichNative::TurnKinds.deleted?(message)
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

  # A janela do histórico (as últimas HISTORY_MAX_INTERACOES mensagens do cliente) conta só as interações reais: o voto
  # escondido, a bolha "abra no celular", o aviso de visualização única e a apagada saem da CONTAGEM antes do corte (sem
  # isto, empurravam mensagens reais para fora da janela). Elas continuam na janela, para o guard ver o turno; o
  # histórico as tira depois (c2y_out_of_history?).
  def janela_do_historico
    return super unless c2y_flag?

    chat = @conversation.messages.chat
    real = chat.incoming.where.not(id: c2y_uncounted_ids(chat))
    desde = real.reorder(created_at: :desc).offset(::Autonomia::Agents::Config::HISTORY_MAX_INTERACOES - 1).pick(:created_at)
    desde ? chat.where(created_at: desde..) : chat
  end

  # Só em SQL (sem carregar as mensagens), nos dois formatos da coluna (objeto e string JSON, Waha::RichNative::JsonColumn):
  # o voto escondido (`c2y_hidden`, só com a flag) e, na caixa WAHA com a flag, a bolha, o aviso de visualização única e
  # a apagada (`deleted_by_contact_at` presente).
  def c2y_uncounted_ids(chat)
    column = 'messages.content_attributes'
    flags = c2y_waha_with_flag? ? UNCOUNTED_FLAGS : %w[c2y_hidden]
    conditions = flags.map { |key| "#{Waha::RichNative::JsonColumn.text(column, :json, key)} = 'true'" }
    conditions << Waha::RichNative::JsonColumn.present(column, :json, 'deleted_by_contact_at') if c2y_waha_with_flag?
    chat.incoming.where(conditions.join(' OR ')).pluck(:id)
  end

  def c2y_stale_choice?(message)
    @c2y_stale ||= {}
    @c2y_stale.fetch(message.id) { @c2y_stale[message.id] = !Waha::RichNative::TurnKinds.choice_current?(message) }
  end

  # Com a flag, as regras do guard; sem ela (ou fora da caixa WAHA), só a da apagada, que vale em qualquer caixa.
  def c2y_turn_skip_reason
    Waha::RichNative::TurnKinds.turn_silence(c2y_turn_incoming, waha: c2y_waha_with_flag?, choices: c2y_flag?)
  rescue StandardError => e
    c2y_report(e, 'c2y_turn_guard_failed')
    nil
  end

  # Erro inesperado do guard: não derruba o turno (a IA segue como na main), mas vai ao rastreador (sem a mensagem
  # original, Waha::RichNative::SafeReport) e ao log (só a classe).
  def c2y_report(error, label)
    Waha::RichNative::SafeReport.capture(error, account: @conversation.account)
    Rails.logger.warn("[autonomia][operate] #{label} conv=#{@conversation.id} #{error.class}")
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
    c2y_disarm_waiting! if reason == STALE_CHOICE_REASON
    c2y_log_event(reason)
    self.class::Result.silenced
  end

  # Silêncio 17 (só voto/resposta retirados no turno): a conversa não fica "esperando resposta" por causa deles. O
  # `waiting_since` só é armado por mensagem do cliente com ele vazio (Message#set_waiting_since_on_incoming_message);
  # se foi armado por uma escolha deste turno, volta a vazio. Armado antes (uma mensagem real anterior), fica.
  # Compare-and-clear: só limpa se o `waiting_since` ainda é o que o voto armou (uma mensagem nova do cliente no meio
  # não perde a espera). Limpo por update_all, sem os callbacks da conversa: os dois que importam para a tela rodam
  # aqui, só quando limpou (a contagem de não lidas filtrada e o `conversation.updated`).
  def c2y_disarm_waiting!
    waiting = Conversation.where(id: @conversation.id).pick(:waiting_since)
    return if waiting.nil?
    return unless c2y_turn_incoming.any? { |message| message.created_at.to_i == waiting.to_i && Waha::RichNative::AiTurn.turn?(message) }

    armed = Conversation.where(id: @conversation.id, waiting_since: waiting)
    cleared = armed.update_all(waiting_since: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    c2y_after_disarm(waiting) if cleared == 1
  rescue StandardError => e
    c2y_report(e, 'c2y_disarm_waiting_failed')
  end

  def c2y_after_disarm(waiting)
    conversation = @conversation.reload
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(conversation.account).conversation_changed!
    conversation.dispatch_conversation_updated_event({ 'waiting_since' => [waiting, nil] })
  end

  # Uma vez por mensagem do cliente (sem índice único: uma duplicata rara na corrida é aceita, como no #1669). O
  # EventLogger nunca levanta; a consulta de antes também não pode derrubar o silêncio (o turno se perderia no retry).
  def c2y_log_event(reason)
    message_id = c2y_turn_message&.id || @reply_to_message_id
    event_type = :"skipped_#{reason}"
    return if @agent.events.exists?(event_type: event_type, conversation_id: @conversation.id, message_id: message_id)

    ::Autonomia::Agents::Operate::EventLogger.create!(agent: @agent, conversation: @conversation, event_type: event_type,
                                                      message_id: message_id, handoff_reason: reason)
  rescue StandardError => e
    c2y_report(e, 'c2y_log_event_failed')
  end
end
