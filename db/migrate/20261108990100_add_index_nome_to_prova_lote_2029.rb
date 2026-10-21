# Prova do #2029 (PR rascunho, nunca vai para a main): índice concurrently, fora da transação.
class AddIndexNomeToProvaLote2029 < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :prova_lote_2029, :nome, algorithm: :concurrently
  end
end
