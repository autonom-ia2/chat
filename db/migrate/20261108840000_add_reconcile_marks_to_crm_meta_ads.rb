# #2285: o marco de início da reconciliação dos formulários da Meta. O ReconcileJob não relê antes do instante em que o
# destino do formulário foi salvo (destination_set_at) nem antes de a Página voltar a receber nesta conta
# (leadgen_receiving_since): lead de antes disso não entra sozinho, como o webhook também não o traria.
# Nascem nulas nas linhas que já existem, e linha nula não é reconciliada até o destino ser salvo de novo. Sem backfill.
class AddReconcileMarksToCrmMetaAds < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_meta_ads_lead_forms, :destination_set_at, :datetime
    add_column :crm_meta_ads_pages, :leadgen_receiving_since, :datetime
  end
end
