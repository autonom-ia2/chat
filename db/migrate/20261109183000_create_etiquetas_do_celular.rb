# Etiquetas do WhatsApp do celular (#1823, F1b): a correspondência entre a etiqueta do app WhatsApp Business de uma caixa
# (`label_wa_id`, o id dela no celular) e a etiqueta daqui (`Label`), com o nome e a cor que ela tem no celular. Tabela do
# fork: `labels` e `inboxes` do Chatwoot não mudam. Apagar a caixa, a etiqueta ou a conta apaga a correspondência junto.
class CreateEtiquetasDoCelular < ActiveRecord::Migration[7.2]
  def change
    create_table :etiquetas_do_celular do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :label, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :label_wa_id, null: false
      t.string :nome, null: false
      t.integer :color_index
      t.boolean :criada_pelo_celular, null: false, default: false
      t.timestamps
      t.index [:inbox_id, :label_wa_id], unique: true
    end
  end
end
