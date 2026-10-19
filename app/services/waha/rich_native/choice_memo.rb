# A regra do Waha::RichNative::TurnKinds.choice_current? com memo, para quem pergunta por muitas mensagens de uma vez
# (chat#1709): o guard do Responder (por turno), o Crm::Ai::ContextBuilder e o Autonomia::Decisores::Estado (por
# chamada). Custo: 1 consulta para o mapa de superadas por conversa (TurnKinds.latest_choice_ids) + 1 por escolha
# vigente distinta (o alvo e o valor guardado); a superada sai pelo mapa, sem consulta.
class Waha::RichNative::ChoiceMemo
  def initialize
    @latest = {}
    @current = {}
  end

  def current?(message)
    @current.fetch(message.id) { @current[message.id] = compute(message) }
  end

  private

  def compute(message)
    choice = Waha::RichNative::TurnKinds.choice_of(message)
    return true if choice.nil?

    latest = (@latest[message.conversation_id] ||= Waha::RichNative::TurnKinds.latest_choice_ids(message.conversation_id))
    newest = latest[[message.sender_type, message.sender_id, choice['target_id'].to_s]]
    return false if newest.present? && newest != message.id

    Waha::RichNative::TurnKinds.stored_choice?(message, choice)
  end
end
