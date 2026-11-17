class Autonomia::Agents::RetrievalQuery
  QUANTITY_QUESTION = /\b(?:quant[oa]s|qual (?:é )?a quantidade|how many)\b[^.!?]*\?\s*\z/i
  NUMBER = /\A[0-9]{1,9}\z/
  QUANTITY_CHANGE = /\A
    (?:
      (?:na\s+verdade|agora|actually)[,:]?\s+(?:(?:quero|ser[áa]|ser[ãa]o|vou\s+fazer|make\s+it)\s+)?|
      (?:vou\s+fazer|vamos\s+fazer|ser[áa]|ser[ãa]o|make\s+it)\s+|
      quero\s+(?:s[óo]|apenas|somente)\s+
    )
    (?:(?:s[óo]|apenas|somente|only|just)\s+)?(?:de\s+)?[0-9]{1,9}
    (?:\s+\p{L}[\p{L}-]*(?:\s+\p{L}[\p{L}-]*){0,2})?[.!]?\z/ix
  HISTORY_MESSAGES = 8
  HISTORY_ITEM_CHARS = 400
  FOLLOWUP_CHARS = 160

  def initialize(query:, history: [])
    @query = query
    @history = Array(history).last(HISTORY_MESSAGES)
  end

  def call
    return @query unless quantity_followup?

    # Only the customer's subject and the last quantity question guide retrieval; old assistant quotes are not facts.
    subject = @history.reverse.find do |turn|
      text = turn[:content].to_s.strip
      turn[:role] == 'user' && !text.empty? && !NUMBER.match?(text) && !QUANTITY_CHANGE.match?(text)
    end
    context = [subject, quantity_question].compact.map { |turn| turn[:content].to_s[0, HISTORY_ITEM_CHARS] }
    context.empty? ? @query : [@query, *context].join("\n")
  end

  private

  def quantity_followup?
    text = @query.to_s.strip
    return false if text.length > FOLLOWUP_CHARS

    QUANTITY_CHANGE.match?(text) || (NUMBER.match?(text) && quantity_question)
  end

  def quantity_question
    turn = @history.last
    turn if turn && turn[:role] == 'assistant' && QUANTITY_QUESTION.match?(turn[:content].to_s)
  end
end
