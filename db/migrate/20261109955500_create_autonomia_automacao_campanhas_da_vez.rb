# #2414 G55 (exemplo 16): a campanha da vez num gatilho recorrente de card ou contato. Uma linha por automação, vez
# (a ocorrência do recorrente) e passo de campanha. A vez fecha pelo estado das execuções dela, lido do banco
# (CampanhaDaOcorrencia); aqui ficam só os lotes que a varredura enfileirou e os que já rodaram, a campanha que saiu e
# quando a vez fechou.
#
# Tabela nova e vazia: sem trava em tabela existente.
class CreateAutonomiaAutomacaoCampanhasDaVez < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_automacao_campanhas_da_vez do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes }, index: false
      t.string :ocorrencia, null: false
      t.string :passo, null: false
      t.integer :lotes
      t.jsonb :lotes_feitos, null: false, default: []
      t.integer :campanha_display_id
      t.datetime :fechada_em
      t.timestamps
    end
    add_index :autonomia_automacao_campanhas_da_vez, %i[automacao_id ocorrencia passo],
              unique: true, name: 'idx_autonomia_automacao_campanhas_da_vez_unica'
  end
end
