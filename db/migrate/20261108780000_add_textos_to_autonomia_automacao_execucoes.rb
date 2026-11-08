# #2679 (lote 2, item c): o texto que um passo de IA ("escrever", "resumir") produziu, pela chave do passo, para um passo
# seguinte ler como valor (`{"$valor": "ia.<passo>"}`). Some quando a execução termina: é cópia de conversa e só vale
# enquanto ela anda.
class AddTextosToAutonomiaAutomacaoExecucoes < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_automacao_execucoes, :textos, :jsonb, default: {}, null: false
  end
end
