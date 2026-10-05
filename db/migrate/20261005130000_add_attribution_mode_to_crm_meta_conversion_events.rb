# Ponte anúncio → landing page → WhatsApp (#1011), Fase 3. Aditiva, tabela do fork.
#
# Cada linha do registro de envios à Meta passa a dizer por onde a venda foi
# atribuída: `ctwa` (clique no anúncio que abre o WhatsApp) ou `website` (botão da
# página, sinais fbc/fbp enviados ao Pixel). Linhas antigas ficam nulas.
class AddAttributionModeToCrmMetaConversionEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_meta_conversion_events, :attribution_mode, :string
  end
end
