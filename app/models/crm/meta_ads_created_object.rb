# O que a plataforma criou na Meta (#2198): uma linha por tentativa de criar, achada pela chave de idempotência da tela.
#
# Situações: `creating` (em andamento), `created` (anúncio criado e pausado), `rolled_back` (um passo falhou e o que
# tinha sido criado foi apagado ou arquivado na Meta), `rollback_failed` (nem apagar deu: o que ficou na Meta está nos
# ids desta linha) e `unconfirmed` (a campanha ficou sem resposta e não apareceu na busca; ver
# Crm::MetaAds::Creation::Attempt). `budget` guarda o orçamento e as datas de quando criou, para a lista de pausados não ler a Meta.
class Crm::MetaAdsCreatedObject < ApplicationRecord
  self.table_name = 'crm_meta_ads_created_objects'

  STATUSES = %w[creating created rolled_back rollback_failed unconfirmed].freeze

  belongs_to :account

  validates :idempotency_key, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  scope :waiting_activation, -> { where(status: 'created', activated_at: nil).where.not(ad_id: nil) }
end
