# Etiquetas do WhatsApp do celular (#1823, F1b), tabelas do fork (`labels`, `inboxes` e `contacts` do Chatwoot não mudam):
# - etiquetas_do_celular: a etiqueta do app WhatsApp Business de uma caixa (`label_wa_id`) ligada à etiqueta daqui
#   (`Label`), com o nome e a cor do celular. `evento_em` é o `at` do último evento aplicado (evento mais velho é
#   descartado); `apagada_em` marca a etiqueta apagada no celular, para um "criada" atrasado não a ressuscitar. Sem
#   `label_id` só a marca de apagada que chegou antes da criação.
# - etiquetas_do_celular_contatos: por contato, se a etiqueta do celular está posta nele e o `at` do último
#   vinculada/desvinculada aplicado, pela mesma regra de ordem.
# Apagar a caixa, a etiqueta, o contato ou a conta apaga as linhas junto.
class CreateEtiquetasDoCelular < ActiveRecord::Migration[7.2]
  def change
    criar_etiquetas_do_celular
    criar_etiquetas_do_celular_contatos
  end

  private

  def criar_etiquetas_do_celular
    create_table :etiquetas_do_celular do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :label, null: true, foreign_key: { on_delete: :cascade }, index: true
      t.string :label_wa_id, null: false
      t.string :nome
      t.integer :color_index
      t.boolean :criada_pelo_celular, null: false, default: false
      t.datetime :evento_em, null: false
      t.datetime :apagada_em
      t.timestamps
      t.index [:inbox_id, :label_wa_id], unique: true
    end
  end

  def criar_etiquetas_do_celular_contatos
    create_table :etiquetas_do_celular_contatos do |t|
      t.references :etiqueta_do_celular, null: false, foreign_key: { to_table: :etiquetas_do_celular, on_delete: :cascade },
                                         index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.boolean :vinculada, null: false, default: false
      t.datetime :evento_em, null: false
      t.timestamps
      t.index [:etiqueta_do_celular_id, :contact_id], unique: true, name: 'index_etiquetas_do_celular_contatos_unicos'
    end
  end
end
