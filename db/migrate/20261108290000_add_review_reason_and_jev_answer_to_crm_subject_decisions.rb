# Medição da IA de assunto (#2018): por que o revisor (modelo maior) foi chamado e o que o Jev respondeu, para medir e
# calibrar os gatilhos. Só colunas nulas, sem índice e sem backfill: nenhuma decisão muda. Os valores estão em
# Crm::SubjectDecision.
class AddReviewReasonAndJevAnswerToCrmSubjectDecisions < ActiveRecord::Migration[7.2]
  def up
    add_column :crm_subject_decisions, :review_reason, :string
    add_column :crm_subject_decisions, :jev_answer, :string
  end

  def down
    remove_column :crm_subject_decisions, :jev_answer
    remove_column :crm_subject_decisions, :review_reason
  end
end
