# A revisão de conversas em lote do Guia (#3158, B8b): "revise as conversas com nota 1 e 2 desta semana e diga os
# motivos". Até 300 conversas por vez, uma chamada de IA por conversa, num job.
#
# Tabela própria, e não `autonomia_guide_tasks`: a tarefa é de ESCRITA (amostra, pausa de segurança, desfazer) e a
# revisão só lê. `ids` guarda as conversas escolhidas (até 5.000), na ordem em que serão lidas; `limite` é até onde
# ler agora (300, mais 300 a cada "ler as que faltam"); `resultados` guarda, por conversa lida, só o id, o número,
# o motivo e a categoria. O texto das mensagens não fica aqui.
class CreateAutonomiaGuideReviews < ActiveRecord::Migration[7.2]
  ANDANDO = "status IN ('na_fila', 'rodando')".freeze

  def change
    create_table :autonomia_guide_reviews do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :turno, foreign_key: { to_table: :autonomia_guide_turns, on_delete: :nullify }
      t.string :status, null: false
      t.string :titulo, null: false
      t.text :pedido, null: false
      t.jsonb :selecao, null: false, default: {}
      t.jsonb :ids, null: false, default: []
      %i[limite posicao lidas falhas].each { |coluna| t.integer coluna, null: false, default: 0 }
      t.jsonb :resultados, null: false, default: []
      t.decimal :custo, precision: 12, scale: 6, null: false, default: 0
      t.string :motivo
      t.datetime :batimento_em
      t.timestamps
    end
    add_index :autonomia_guide_reviews, [:account_id, :status]
    # Uma revisão andando por pessoa: dois pedidos seguidos (ou o modelo chamando de novo) não começam duas.
    add_index :autonomia_guide_reviews, [:account_id, :user_id], unique: true, where: ANDANDO, name: 'idx_autonomia_guide_reviews_uma_andando'
    # O vigia procura, entre as que andam, a que ficou sem batimento.
    add_index :autonomia_guide_reviews, :batimento_em, where: ANDANDO, name: 'idx_autonomia_guide_reviews_batimento'
  end
end
