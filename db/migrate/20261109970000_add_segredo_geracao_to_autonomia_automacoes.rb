# #2670 (G13): a geração do segredo do passo "webhook" mora na própria automação. Trocar o segredo sobe a geração num
# UPDATE só (segredo_geracao + 1), e nenhuma outra gravação a volta: no internal_attributes da conta, quem regravasse o
# hash inteiro com uma conta lida antes da troca reativava o segredo anterior.
class AddSegredoGeracaoToAutonomiaAutomacoes < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_automacoes, :segredo_geracao, :integer, default: 0, null: false
  end
end
