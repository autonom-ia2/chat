# #2499 (PR3a): o instante em que a automação foi ligada. Os gatilhos de tempo não agem na ocorrência anterior a ele:
# ligar às 8h um "no dia do aniversário, às 9h" não manda o de ontem. A janela de 1 dia continua sendo só para pane.
# Nasce nula nas que já existem; aí vale a hora da versão ativa (Tempo.ligada_desde).
class AddLigadaEmToAutonomiaAutomacoes < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_automacoes, :ligada_em, :datetime
  end
end
