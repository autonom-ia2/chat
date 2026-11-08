# Objetivo do conjunto de anúncios (#2521): com o destino UNDEFINED, é ele que diz se o anúncio traz conversa
# (Crm::MetaAds::Panel::AdDestinations). Preenchido pela leitura dos conjuntos (Crm::MetaAds::Insights::Destinations).
class AddOptimizationGoalToCrmMetaAdObjects < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_meta_ad_objects, :optimization_goal, :string
  end
end
