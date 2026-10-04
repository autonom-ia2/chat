# O que o Guia lembra entre conversas (#933).
#
# Cada conversa começava do zero: a pessoa repetia apelidos ("funil do Zé"),
# combinados ("relatório é do mês corrente") e o jeito de falar. Uma memória é
# uma frase curta, da pessoa (`user_id`) ou da corretora (`user_id` nulo).
#
# Conta apagada leva tudo; pessoa apagada leva as dela. A conversa onde a
# memória nasceu pode sumir sem levar a memória (`turno_id` vira nulo).
class CreateAutonomiaGuideMemorias < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_guide_memorias do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, foreign_key: { on_delete: :cascade }
      t.string :texto, limit: 200, null: false
      t.bigint :autor_id, null: false
      t.references :turno, foreign_key: { to_table: :autonomia_guide_turns, on_delete: :nullify }
      t.timestamps
    end
    add_index :autonomia_guide_memorias, [:account_id, :user_id]
  end
end
