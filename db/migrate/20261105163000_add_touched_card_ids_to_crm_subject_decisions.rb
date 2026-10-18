# Vários assuntos numa mensagem (#1693): a decisão guarda os cards que a mensagem tocou, o principal primeiro. Nulo é
# "não calculado" (flag desligada, dúvida, falha): a IA do CRM relê o card em foco, como no #1675. Lista vazia é "a
# mensagem não toca nenhum assunto" ("obrigado!"): nada é avaliado.
class AddTouchedCardIdsToCrmSubjectDecisions < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_subject_decisions, :touched_card_ids, :bigint, array: true
  end
end
