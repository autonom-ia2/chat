# Ligação de uma conversa ao anúncio da Meta que a trouxe (#1073, F2b). Uma linha por toque de anúncio
# (`touch_key`: o clique da Meta ou a origem do toque), gravada por Crm::MetaAds::Links::Linker.
#
# `certainty`, do mais forte ao mais fraco:
# - `ad`: o ID do anúncio veio no próprio toque (clique para o WhatsApp, ou ID no texto do anúncio do site);
# - `ad_name`: a campanha veio por ID e o anúncio foi achado pelo nome dentro dela;
# - `campaign`: só a campanha (ou o conjunto) é conhecida;
# - `unknown`: veio de anúncio da Meta, mas sem dizer qual.
class Crm::MetaAdLink < ApplicationRecord
  self.table_name = 'crm_meta_ad_links'

  CERTAINTIES = %w[ad ad_name campaign unknown].freeze
  ORIGINS = %w[whatsapp site].freeze

  belongs_to :account
  belongs_to :conversation

  validates :touch_key, :touched_at, presence: true
  validates :certainty, inclusion: { in: CERTAINTIES }
  validates :origin, inclusion: { in: ORIGINS }
end
