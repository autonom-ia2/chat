# == Schema Information
#
# Table name: campaign_free_texts
#
#  id            :bigint           not null, primary key
#  content       :text             not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  campaign_id   :bigint           not null
#
# Indexes
#
#  index_campaign_free_texts_on_account_id   (account_id)
#  index_campaign_free_texts_on_campaign_id  (campaign_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campaign_id => campaigns.id) ON DELETE => cascade
#
# A mensagem escrita da campanha para quem falou com a caixa nas últimas 24 horas (#1335). Tabela do fork: a campanha
# do Chatwoot não ganha coluna. Os campos ficam na sintaxe do catálogo e são conferidos por
# CampaignJourney::ConversaAberta::Texto antes de gravar.
class CampaignFreeText < ApplicationRecord
  belongs_to :account
  belongs_to :campaign

  validates :content, presence: true, length: { maximum: CampaignJourney::ConversaAberta::Texto::MAX_CHARS }
  validates :campaign_id, uniqueness: true
  validate :same_account

  private

  def same_account
    errors.add(:campaign, 'must belong to the same account') if campaign && campaign.account_id != account_id
  end
end
