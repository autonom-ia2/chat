# == Schema Information
#
# Table name: campaign_version_contacts
#
#  id                        :bigint           not null, primary key
#  fase                      :string           not null
#  versao                    :integer          not null
#  created_at                :datetime         not null
#  account_id                :bigint           not null
#  campaign_audience_link_id :bigint           not null
#  contact_id                :bigint           not null
#
# Indexes
#
#  idx_campaign_version_contacts_link_contact          (campaign_audience_link_id,contact_id) UNIQUE
#  idx_campaign_version_contacts_link_versao           (campaign_audience_link_id,versao,fase)
#  index_campaign_version_contacts_on_account_id       (account_id)
#  index_campaign_version_contacts_on_contact_id       (contact_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campaign_audience_link_id => campaign_audience_links.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#
# #3099: qual das duas versões da mensagem cada pessoa recebeu. 'teste' = sorteada para o teste (no público pequeno,
# todo mundo); 'resto' = recebeu depois da escolha, com a versão escolhida. Quem escreve é CampaignJourney::DuasVersoes
# (insert em lote, como o grupo de controle); quem lê é o envio (a versão de cada pessoa) e o resultado.
class CampaignVersionContact < ApplicationRecord
  FASES = %w[teste resto].freeze

  belongs_to :account
  belongs_to :campaign_audience_link
  belongs_to :contact

  validates :versao, inclusion: { in: CampaignJourney::DuasVersoes::VERSOES }
  validates :fase, inclusion: { in: FASES }
  validates :contact_id, uniqueness: { scope: :campaign_audience_link_id }
end
