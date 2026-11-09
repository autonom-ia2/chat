# #2414 G55 (exemplo 16): a campanha da vez num gatilho recorrente de card ou contato. Uma linha por automação, vez
# (a ocorrência do recorrente) e passo de campanha, com o total de cards que a vez espera e quantos já chegaram ao passo,
# saíram por outro caminho ou nem abriram execução. A campanha sai quando a conta fecha (CampanhaDaOcorrencia).
#
# Tabela nova e vazia: sem trava em tabela existente.
class CreateAutonomiaAutomacaoCampanhasDaVez < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_automacao_campanhas_da_vez do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes }, index: false
      t.string :ocorrencia, null: false
      t.string :passo, null: false
      t.integer :esperados
      t.integer :chegadas, null: false, default: 0
      t.integer :saidas, null: false, default: 0
      t.integer :sem_execucao, null: false, default: 0
      t.bigint :primeira_execucao_id
      t.integer :campanha_display_id
      t.datetime :fechada_em
      t.timestamps
    end
    add_index :autonomia_automacao_campanhas_da_vez, %i[automacao_id ocorrencia passo],
              unique: true, name: 'idx_autonomia_automacao_campanhas_da_vez_unica'
  end
end
