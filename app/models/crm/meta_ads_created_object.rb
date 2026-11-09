# O que a plataforma criou na Meta (#2198): uma linha por tentativa de criar, achada pela chave de idempotência da tela.
#
# Situações: `creating` (em andamento), `created` (anúncio criado e pausado), `rolled_back` (um passo falhou e o que
# tinha sido criado foi apagado ou arquivado na Meta), `rollback_failed` (nem apagar deu: o que ficou na Meta está nos
# ids desta linha) e `unconfirmed` (a campanha ficou sem resposta e não apareceu na busca; ver
# Crm::MetaAds::Creation::Attempt). `budget` guarda o orçamento e as datas de quando criou, para a lista de pausados não ler a Meta.
#
# Impulsionar post (#2522): `source_post_id` e `source_post_network` ('instagram' ou 'facebook') guardam o post de
# origem. Anúncio com criativo novo fica com os dois nulos, como as linhas de antes deles.
class Crm::MetaAdsCreatedObject < ApplicationRecord
  self.table_name = 'crm_meta_ads_created_objects'

  STATUSES = %w[creating created rolled_back rollback_failed unconfirmed].freeze

  belongs_to :account

  validates :idempotency_key, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  scope :waiting_activation, -> { where(status: 'created', activated_at: nil).where.not(ad_id: nil) }

  # Os anúncios que impulsionaram estes posts por aqui e já foram ativados (pausado sem nunca rodar não teve anúncio):
  # { post_id => [ad_id, ...] }, o mais novo primeiro. Uma consulta, sem chamar a Meta. Ativado aqui
  # (Crm::MetaAds::Creation::Levels, ou Activation#held_by) ou no Gerenciador da Meta, visto pela leitura dos pausados
  # (#2739, Crm::MetaAds::Creation::PausedAds). "Ativado" é a pessoa ter ligado o anúncio, como no Ativar daqui.
  def self.ads_by_post(account_id, network, post_ids)
    boosting(account_id, network, post_ids).pluck(:source_post_id, :ad_id)
                                           .each_with_object({}) { |(post_id, ad_id), ads| (ads[post_id] ||= []) << ad_id }
  end

  # Post impulsionado mais de uma vez (#2739): cada anúncio tem os próprios comentários, e o post leva a todos, sem
  # corte (um por vez que a pessoa impulsionou). [{ id:, name:, created_at: }], o mais novo primeiro; a data separa
  # anúncios com o mesmo nome.
  def self.ads_of_post(account_id, network, post_id)
    boosting(account_id, network, [post_id]).pluck(:ad_id, :name, :created_at)
                                            .map { |id, name, created_at| { id: id, name: name, created_at: created_at.iso8601 } }
  end

  def self.boosting(account_id, network, post_ids)
    ids = Array(post_ids).map(&:to_s).compact_blank
    return none if ids.empty?

    where(account_id: account_id, source_post_network: network, source_post_id: ids, status: 'created')
      .where.not(activated_at: nil).where.not(ad_id: nil).order(activated_at: :desc, id: :desc)
  end
  private_class_method :boosting
end
