# == Schema Information
#
# Table name: autonomia_prospecting_lists
#
#  id          :bigint           not null, primary key
#  description :text
#  metadata    :jsonb            not null
#  name        :string           not null
#  status      :integer          default("active"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  user_id     :bigint
#
# Indexes
#
#  index_autonomia_prospecting_lists_on_account_id           (account_id)
#  index_autonomia_prospecting_lists_on_account_id_and_name  (account_id,name)
#  index_autonomia_prospecting_lists_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Autonomia::Prospecting::List < ApplicationRecord
  self.table_name = 'autonomia_prospecting_lists'

  belongs_to :account
  belongs_to :user, optional: true

  has_many :list_leads, class_name: 'Autonomia::Prospecting::ListLead', foreign_key: :prospect_list_id, dependent: :destroy,
                        inverse_of: :list
  has_many :leads, through: :list_leads, source: :lead

  enum status: { active: 0, archived: 1 }

  validates :name, presence: true

  # Todas as etiquetas que o segmento desta lista já gerou (chat#713). Refazer o segmento com outro nome cria outra
  # etiqueta, e a campanha que começou com a antiga continua com ela na audiência: descarte e recusa precisam achar as
  # duas. Lista gravada antes do histórico só tem a última etiqueta.
  def segment_label_ids
    segment = metadata.to_h['campaign_segment'].to_h
    [*segment['label_ids'], segment['label_id']].map(&:to_i).select(&:positive?).uniq
  end
end
