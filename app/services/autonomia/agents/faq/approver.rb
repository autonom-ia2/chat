# Revisão de uma sugestão de FAQ (#284 · 2b): aprovar (com ou sem edição) grava o par na base do
# agente; ignorar só marca. Transições SÓ a partir de `pending`, sob lock (dois revisores não aprovam
# a mesma sugestão duas vezes = duas entries).
class Autonomia::Agents::Faq::Approver
  class NotPending < StandardError; end

  def initialize(suggestion:, user:)
    @suggestion = suggestion
    @user = user
  end

  # question/answer opcionais: quando mudam, a sugestão vira `edited` (senão `approved`).
  # -> KnowledgeEntry criada. Levanta NotPending / RecordInvalid / EmbeddingError.
  def approve!(question: nil, answer: nil)
    entry = nil
    @suggestion.with_lock do
      raise NotPending unless @suggestion.pending?

      changed = apply_edits(question, answer)
      @suggestion.validate!
      entry = Autonomia::Agents::Faq::KnowledgeWriter.new(agent: @suggestion.agent).write!(@suggestion)
      @suggestion.update!(status: changed ? :edited : :approved, reviewed_by: @user, reviewed_at: Time.current)
    end
    entry
  end

  def ignore!
    @suggestion.with_lock do
      raise NotPending unless @suggestion.pending?

      @suggestion.update!(status: :ignored, reviewed_by: @user, reviewed_at: Time.current)
    end
    @suggestion
  end

  private

  # -> true quando algum texto mudou de fato.
  def apply_edits(question, answer)
    before = [@suggestion.question, @suggestion.answer]
    @suggestion.question = question.to_s.strip if question.present?
    @suggestion.answer = answer.to_s.strip if answer.present?
    before != [@suggestion.question, @suggestion.answer]
  end
end
