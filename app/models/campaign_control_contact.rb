# == Schema Information
#
# Table name: campaign_control_contacts
#
#  id                        :bigint           not null, primary key
#  created_at                :datetime         not null
#  account_id                :bigint           not null
#  campaign_audience_link_id :bigint           not null
#  contact_id                :bigint           not null
#
# Indexes
#
#  idx_campaign_control_contacts_link_contact            (campaign_audience_link_id,contact_id) UNIQUE
#  index_campaign_control_contacts_on_account_id         (account_id)
#  index_campaign_control_contacts_on_contact_id         (contact_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campaign_audience_link_id => campaign_audience_links.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#
# #3098: quem foi sorteado para ficar sem receber a campanha (o grupo de controle). Quem escreve é
# CampaignJourney::GrupoDeControle, no envio; quem lê é a tela de resultado, para comparar quem recebeu com quem não.
class CampaignControlContact < ApplicationRecord
  belongs_to :account
  belongs_to :campaign_audience_link
  belongs_to :contact
end
