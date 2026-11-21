# == Schema Information
#
# Table name: campaign_audience_links
#
#  id                 :bigint           not null, primary key
#  campaign_type      :string           not null
#  grupo_de_controle_pct :integer        default(0), not null
#  janela_de_compra_dias :integer        default(7), not null
#  variable_bindings  :jsonb            not null
#  variable_defaults  :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  campaign_id        :bigint           not null
#  campaign_import_id :bigint
#
# Indexes
#
#  index_campaign_audience_links_on_account_id                      (account_id)
#  index_campaign_audience_links_on_campaign_import_id              (campaign_import_id)
#  index_campaign_audience_links_on_campaign_type_and_campaign_id  (campaign_type,campaign_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campaign_import_id => campaign_imports.id) ON DELETE => nullify
#
# Públicos (#1005): which audience a campaign sends to. A fork table, so Chatwoot's campaign
# tables get no new column (PRD §8.0-4). campaign_import is nil after the audience is
# deleted: the campaign keeps its results and sends to no one.
#
# #3098: `janela_de_compra_dias` (por quantos dias depois do envio a compra conta) e `grupo_de_controle_pct` (a parte do
# público sorteada para não receber; 0 = sem grupo), escolhidos na revisão da campanha.
class CampaignAudienceLink < ApplicationRecord
  JANELAS_DE_COMPRA = [7, 15, 30].freeze
  GRUPOS_DE_CONTROLE = [0, 5, 10, 20].freeze

  belongs_to :account
  belongs_to :campaign, polymorphic: true
  belongs_to :campaign_import, optional: true
  has_many :campaign_control_contacts, dependent: :delete_all

  validates :campaign_id, uniqueness: { scope: :campaign_type }
  validates :janela_de_compra_dias, inclusion: { in: JANELAS_DE_COMPRA }
  validates :grupo_de_controle_pct, inclusion: { in: GRUPOS_DE_CONTROLE }
  validate :same_account

  def self.for_campaign(campaign)
    find_by(campaign_type: campaign.class.name, campaign_id: campaign.id)
  end

  private

  # #1005 B5: a link never crosses accounts.
  def same_account
    errors.add(:campaign, 'must belong to the same account') if campaign && campaign.account_id != account_id
    errors.add(:campaign_import, 'must belong to the same account') if campaign_import && campaign_import.account_id != account_id
  end
end
