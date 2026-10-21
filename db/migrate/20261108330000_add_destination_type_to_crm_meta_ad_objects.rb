# Para onde o conjunto de anúncios leva (#2054), como a Meta manda em `destination_type` (WHATSAPP, WEBSITE, ON_VIDEO…):
# o painel separa os anúncios que trazem conversa dos outros sem tratar anúncio novo de WhatsApp como de site.
class AddDestinationTypeToCrmMetaAdObjects < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_meta_ad_objects, :destination_type, :string
  end
end
