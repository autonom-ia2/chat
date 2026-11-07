# Lote 4 da Automação livre (#2682): a hora em que o gatilho aconteceu de novo com a execução ainda aberta. O "esperar
# até" lê `gatilho.repetiu` por ela (a 2ª falta dentro dos 30 dias). Nula enquanto o gatilho não se repete.
class AddRepetiuEmToAutonomiaAutomacaoExecucoes < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_automacao_execucoes, :repetiu_em, :datetime
  end
end
