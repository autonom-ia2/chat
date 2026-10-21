# Medição da IA de assunto (#2018): por que o revisor (modelo maior) foi chamado e o que o Jev respondeu, para medir e
# calibrar os gatilhos. Só colunas nulas, sem índice e sem backfill: nenhuma decisão muda. Os valores estão em
# Crm::SubjectDecision.
class AddReviewReasonAndJevAnswerToCrmSubjectDecisions < ActiveRecord::Migration[7.2]
  def up
    # ADD COLUMN pede trava exclusiva rápida numa tabela escrita a cada mensagem: atrás de uma transação longa, desiste
    # em 5 s em vez de enfileirar leitura e escrita atrás dela (rodar de novo depois). LOCAL: vale só nesta transação.
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :crm_subject_decisions, :review_reason, :string
    add_column :crm_subject_decisions, :jev_answer, :string
  end

  def down
    remove_column :crm_subject_decisions, :jev_answer
    remove_column :crm_subject_decisions, :review_reason
  end
end
