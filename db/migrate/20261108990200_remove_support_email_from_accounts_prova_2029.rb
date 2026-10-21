# Prova NEGATIVA do #2029 (PR rascunho, nunca vai para a main): remove coluna que o código ainda usa, sem anúncio em
# db/retiradas.yml. O job "Migrations do lote" tem de ficar vermelho.
class RemoveSupportEmailFromAccountsProva2029 < ActiveRecord::Migration[7.2]
  def change
    remove_column :accounts, :support_email, :string, limit: 100
  end
end
