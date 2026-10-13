# == Schema Information
#
# Table name: campaign_free_text_deliveries
#
#  id                    :bigint           not null, primary key
#  fell_back_at          :datetime
#  message_id            :bigint
#  source_id             :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  campaign_id           :bigint           not null
#  campaign_recipient_id :bigint           not null
#  inbox_id              :bigint           not null
#
# Indexes
#
#  idx_campaign_free_text_deliveries_recipient          (campaign_recipient_id) UNIQUE
#  idx_campaign_free_text_deliveries_source             (inbox_id,source_id) UNIQUE
#  index_campaign_free_text_deliveries_on_campaign_id  (campaign_id)
#  index_campaign_free_text_deliveries_on_message_id   (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campaign_id => campaigns.id) ON DELETE => cascade
#
# Quem recebeu a mensagem escrita da campanha (#1335): o id da Meta da mensagem livre (source_id) e a Message gravada na
# conversa (message_id; o Híbrido troca o source_id dela quando assume o envio). Se a Meta recusar com 131047
# (janela fechada), a pessoa recebe o modelo uma vez só (fell_back_at).
class CampaignFreeTextDelivery < ApplicationRecord
  belongs_to :account
  belongs_to :campaign

  validates :source_id, :inbox_id, :campaign_recipient_id, presence: true

  def fell_back?
    fell_back_at.present?
  end
end
