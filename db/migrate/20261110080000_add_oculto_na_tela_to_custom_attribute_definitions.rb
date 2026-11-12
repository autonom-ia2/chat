# #2435: o atributo personalizado que serve só para uso interno (um contador da automação, o código de outro sistema)
# pode sair da tela do card, do contato, da empresa e da conversa. Continua gravado, filtrável, na API e lido pela
# automação e pelas IAs. Coluna aditiva com padrão constante: nenhum atributo existente muda, e não há backfill.
class AddOcultoNaTelaToCustomAttributeDefinitions < ActiveRecord::Migration[7.2]
  def change
    add_column :custom_attribute_definitions, :oculto_na_tela, :boolean, default: false, null: false
  end
end
