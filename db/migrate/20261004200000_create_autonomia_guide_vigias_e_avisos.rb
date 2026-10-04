# O Guia volta sozinho quando algo medido na conta cruza um limite (#935).
#
# A vigia é uma leitura salva da conta com um gatilho numérico. O aviso é o que
# chega à pessoa quando a leitura cruza o gatilho: um por pessoa, com `chave`
# única para nunca repetir, e `sinal` só com ids e números — nenhum texto do que
# foi lido.
#
# Conta apagada leva tudo; pessoa apagada leva os avisos dela. A conversa onde o
# aviso apareceu pode sumir sem levar o aviso (`turno_id` vira nulo).
class CreateAutonomiaGuideVigiasEAvisos < ActiveRecord::Migration[7.2]
  def change
    criar_vigias
    criar_avisos
  end

  private

  def criar_vigias
    create_table :autonomia_guide_vigias do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :criado_por, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :nome, limit: 120, null: false
      t.string :origem, null: false, default: 'pessoa'
      t.jsonb :leitura, null: false, default: {}
      t.jsonb :gatilho, null: false, default: {}
      t.jsonb :para_quem, null: false, default: []
      t.string :gravidade, null: false, default: 'info'
      t.boolean :ativa, null: false, default: true
      t.datetime :silenciada_ate
      t.jsonb :linha_de_base, null: false, default: {}
      t.string :ultima_janela
      t.timestamps
    end
    add_index :autonomia_guide_vigias, [:account_id, :ativa]
  end

  def criar_avisos
    create_table :autonomia_guide_avisos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :chave, null: false
      t.string :estado, null: false, default: 'novo'
      t.string :gravidade, null: false, default: 'info'
      t.jsonb :sinal, null: false, default: {}
      t.text :texto, null: false
      t.references :turno, foreign_key: { to_table: :autonomia_guide_turns, on_delete: :nullify }
      t.timestamps
    end
    add_index :autonomia_guide_avisos, :chave, unique: true
    add_index :autonomia_guide_avisos, [:account_id, :user_id, :estado]
    add_index :autonomia_guide_avisos, :created_at
  end
end
