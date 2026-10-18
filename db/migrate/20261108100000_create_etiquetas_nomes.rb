# Nome livre da etiqueta (#1823, F1a): o que o atendente digitou ao criar ou editar ("Novo Cliente"), um por etiqueta.
# O `labels.title` continua a chave técnica de filtros, URL, automações e API, e a tabela `labels` do Chatwoot não
# muda. Apagar a etiqueta (ou a conta) apaga o nome junto. Tabela nova: os índices nascem dentro do create_table.
class CreateEtiquetasNomes < ActiveRecord::Migration[7.2]
  def change
    create_table :etiquetas_nomes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :label, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :nome, null: false, limit: 80
      t.timestamps
    end
  end
end
