# Decisor (#858): a pergunta que a conta faz sobre cada conversa ("é lead?") e as decisões tomadas.
#
# As duas tabelas são novas, então a migração é só aditiva. A decisão guarda a resposta por mensagem:
# duas regras que perguntam ao mesmo Decisor sobre a mesma mensagem reaproveitam uma só pergunta.
class CreateAutonomiaDecisores < ActiveRecord::Migration[7.2]
  def change
    criar_decisores
    criar_decisoes
  end

  private

  def criar_decisores
    create_table :autonomia_decisores do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :nome, null: false
      t.text :pergunta, null: false
      t.text :instrucoes
      t.jsonb :respostas, null: false, default: []
      t.jsonb :exemplos, null: false, default: []
      t.jsonb :campos, null: false, default: []
      t.decimal :certeza_minima, precision: 3, scale: 2, null: false, default: 0.80
      t.integer :perguntas_count, null: false, default: 0
      t.integer :duvidas_count, null: false, default: 0
      t.integer :correcoes_count, null: false, default: 0
      t.datetime :ultima_pergunta_em
      t.timestamps
    end
    add_index :autonomia_decisores, [:account_id, :nome], unique: true
  end

  def criar_decisoes
    create_table :autonomia_decisor_decisoes do |t|
      t.references :decisor, null: false, index: false, foreign_key: { to_table: :autonomia_decisores, on_delete: :cascade }
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :automation_rule, foreign_key: { on_delete: :nullify }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.string :resposta
      t.decimal :certeza, precision: 4, scale: 3
      t.jsonb :campos_extraidos, null: false, default: {}
      t.string :status, null: false
      # Cada regra que ficou esperando esta decisão ({regra, indice}): quando a dúvida se resolve, todas retomam.
      t.jsonb :esperas, null: false, default: []
      # Cada regra que já seguiu depois desta decisão: a retomada repetida não roda os passos duas vezes.
      t.jsonb :seguidas, null: false, default: []
      t.text :motivo
      t.references :resolvida_por, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :autonomia_decisor_decisoes, [:decisor_id, :conversation_id, :message_id], unique: true,
                                                                                         name: 'idx_autonomia_decisoes_por_mensagem'
    add_index :autonomia_decisor_decisoes, [:account_id, :status, :created_at], name: 'idx_autonomia_decisoes_fila'
  end
end
