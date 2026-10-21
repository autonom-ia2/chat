# Prova do #2029 (PR rascunho, nunca vai para a main): tabela nova com chave estrangeira sem column:.
class CreateProvaLote2029 < ActiveRecord::Migration[7.2]
  def change
    create_table :prova_lote_2029 do |t|
      t.references :account, null: false, foreign_key: true
      t.string :nome
      t.timestamps
    end
  end
end
