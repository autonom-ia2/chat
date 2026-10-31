# #2424: o que a IA escolheu, com que certeza e por quê, na linha `ai_seen` de cada comentário que a IA leu.
class AddAiDecisionToCrmMetaAdsCommentActions < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_meta_ads_comment_actions, :ai_decision, :string
    add_column :crm_meta_ads_comment_actions, :ai_confidence, :decimal, precision: 4, scale: 3
    add_column :crm_meta_ads_comment_actions, :ai_reason, :text
  end
end
