# Meta do mês de uma pessoa num funil de Vender (#1991, F4 do #1871), em centavos na moeda do funil. Quem grava é só o
# Crm::Metas::Salvar; quem lê é a gaveta "Metas do mês" (Crm::Metas::Gaveta) e o topo de "Só eu" (Crm::Metas::DaPessoa).
class Crm::PersonGoal < ApplicationRecord
  self.table_name = 'crm_person_goals'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :user

  validates :month, presence: true
  validates :target_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true
  validates :user_id, uniqueness: { scope: %i[pipeline_id month] }
end
