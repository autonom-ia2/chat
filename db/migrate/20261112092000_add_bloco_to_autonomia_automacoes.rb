# #2933 (Usar outra automação): a automação marcada como bloco não tem gatilho próprio e só roda quando outra a usa. A
# marca é da automação, não da versão: vale para todas as versões e a lista do editor filtra por ela. Coluna nova com
# padrão constante (o Postgres não reescreve a tabela), sem índice e sem backfill: toda automação que já existe continua
# não sendo bloco.
class AddBlocoToAutonomiaAutomacoes < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_automacoes, :bloco, :boolean, default: false, null: false
  end
end
