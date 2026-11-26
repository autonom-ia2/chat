# Agente pronto Seguro Viagem Universal (#3211): o acesso do corretor à seguradora, um por agente. Tabela nova e vazia:
# nenhuma trava em tabela que já existe, nenhum job enfileirado.
#
# `login` e `senha` são text porque o ActiveRecord::Encryption grava o valor cifrado com cabeçalho, maior que o original.
# `login_dica` é a única parte do login que a tela vê. `capacidades` guarda o que o acesso pode fazer, pelas nossas chaves.
#
# Chaves: agente em cascata (apagar o agente apaga o acesso); conta sem cascata, como as outras tabelas da conta: a
# exclusão da conta (Autonomia::ExclusaoDaConta) apaga as linhas antes do DELETE da conta.
class CreateAutonomiaAcessosDaSeguradora < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_acessos_da_seguradora do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :autonomia_agent, null: false, index: { unique: true },
                                     foreign_key: { to_table: :autonomia_agents, on_delete: :cascade }
      t.string :seguradora, null: false, default: 'universal'
      t.text :login
      t.text :senha
      t.string :login_dica
      t.string :estado, null: false, default: 'nao_conferido'
      t.datetime :conferido_em
      t.string :motivo
      t.jsonb :capacidades, null: false, default: {}
      t.timestamps
    end
  end
end
