# O que o agente de IA faz com cada mensagem do cliente que o recebimento WAHA marca (chat#1709). Usado por
# Waha::RichNative::AgentTurnGuard, que só pergunta na caixa WAHA comum com a flag `whatsapp_rich_native`.
module Waha::RichNative::TurnKinds
  UNSUPPORTED_KEY = 'is_unsupported'.freeze
  DELETED_KEY = 'deleted_by_contact_at'.freeze
  VIEW_ONCE_KEY = 'view_once_unavailable'.freeze

  module_function

  # :unsupported (bolha "abra no celular" ou aviso de visualização única), :deleted (apagada pelo cliente) ou nil
  # (mensagem real, que a IA responde).
  def kind(message)
    attributes = message.content_attributes.to_h
    return :deleted if attributes[DELETED_KEY].present?

    :unsupported if attributes[UNSUPPORTED_KEY] == true || attributes[VIEW_ONCE_KEY] == true
  end

  # Fora do histórico que vai à IA: apagada e aviso de visualização única (não há conteúdo para ler).
  def out_of_history?(message)
    attributes = message.content_attributes.to_h
    attributes[DELETED_KEY].present? || attributes[VIEW_ONCE_KEY] == true
  end

  # O motivo para calar o turno, ou nil quando há mensagem real nele. Só quando TODAS são sem conteúdo.
  def silent_reason(turn_messages)
    kinds = turn_messages.map { |message| kind(message) }
    return if kinds.empty? || kinds.include?(nil)

    kinds.include?(:unsupported) ? Waha::RichNative::AgentTurnGuard::UNSUPPORTED_REASON : Waha::RichNative::AgentTurnGuard::DELETED_REASON
  end

  # O motivo para calar o turno inteiro, a regra do settle (Waha::RichNative::AgentTurnGuard) e do rastro da bolha
  # (Waha::RichNative::UnsupportedTurnJob): o voto/resposta que não vale mais sai do turno; sem nada que sobre, a
  # escolha retirada; na caixa WAHA com a flag (`waha`), o que sobra sem conteúdo (silent_reason). nil: responder.
  # `choices`: aplicar o filtro do voto retirado (só com a flag). Fora da caixa WAHA com a flag, só a regra da apagada
  # (`deleted_by_contact_at`, que só existe quando algo a gravou: #1702b na Cloud, o conector): turno só de apagadas.
  def turn_silence(turn_messages, waha: true, choices: true)
    remaining = choices ? turn_messages.select { |message| choice_current?(message) } : turn_messages
    return Waha::RichNative::AgentTurnGuard::STALE_CHOICE_REASON if turn_messages.any? && remaining.empty?

    waha ? silent_reason(remaining) : deleted_reason(remaining)
  end

  def deleted_reason(turn_messages)
    Waha::RichNative::AgentTurnGuard::DELETED_REASON if turn_messages.any? && turn_messages.all? { |message| deleted?(message) }
  end

  def deleted?(message)
    message.content_attributes.to_h[DELETED_KEY].present?
  end

  # Voto ou resposta ao convite do turno (Waha::RichNative::AiTurn): a escolha ainda é a guardada? Mensagem que não é
  # escolha: sempre.
  def choice_current?(message)
    choice = message.content_attributes.to_h[Waha::RichNative::AiTurn::CHOICE_KEY]
    return true unless choice.is_a?(Hash)

    target = Message.find_by(id: choice['target_id'], conversation_id: message.conversation_id)
    return false if target.nil?

    voter = { sender_type: message.sender_type, sender_id: message.sender_id }
    case choice['kind']
    when 'poll_vote' then Waha::RichNative::PollVotes.current?(target, **voter, titles: choice['choice'])
    when 'event_response' then Waha::RichNative::EventResponses.current?(target, **voter, response: choice['choice'])
    else true
    end
  end
end
