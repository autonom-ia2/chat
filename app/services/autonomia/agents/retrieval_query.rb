class Autonomia::Agents::RetrievalQuery
  NUMBER = /\A[0-9]{1,9}\z/
  YES_NO = /\A(?:sim|n[ãa]o|yes|no)[.!]?\z/i
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
  DETAIL_WORDS = 4

  def initialize(query:, history: [])
    @query = query
    @history = Array(history).last(HISTORY_MESSAGES)
  end

  def call
    return @query unless contextual_followup?

    # Customer details and the last question guide search, never the assistant's previous quote or answer.
    context = [*subject_context, last_question].compact.map { |text| text[0, HISTORY_ITEM_CHARS] }
    context.empty? ? @query : [@query, *context].join("\n")
  end

  private

  def contextual_followup?
    text = @query.to_s.strip
    return false if text.length > FOLLOWUP_CHARS

    QUANTITY_CHANGE.match?(text) || (short_answer?(text) && last_question)
  end

  def short_answer?(text)
    NUMBER.match?(text) || YES_NO.match?(text)
  end

  def subject_context
    turns = @history.reverse.select { |turn| subject_turn?(turn) }
    latest = turns.first&.fetch(:content).to_s
    # A short detail (species, model, etc.) needs the previous subject; a complete question stands on its own.
    count = latest.include?('?') || latest.split.size > DETAIL_WORDS ? 1 : 2
    turns.first(count).map { |turn| turn[:content].to_s }
  end

  def subject_turn?(turn)
    return false unless turn[:role] == 'user'

    text = turn[:content].to_s.strip
    !text.empty? && !short_answer?(text) && !QUANTITY_CHANGE.match?(text)
  end

  def last_question
    turn = @history.last
    return unless turn && turn[:role] == 'assistant'

    turn[:content].to_s[/([^.!?\n]+\?)\s*\z/, 1]&.strip
  end
end
