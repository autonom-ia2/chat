# Uma análise do consultor de anúncios da Meta (#1110, F5): os fatos, as regras, a decisão do dia e o texto que
# a IA escreveu para ela. Criada e escrita por Crm::MetaAds::Advisor::Analysis.
#
# Um run por conta · dia · idioma · assinatura (índice único). A assinatura cobre a versão das regras, a das
# instruções da IA e o tipo, o anúncio e a variante de cada ação: a mesma decisão reaproveita o run e o texto
# já escrito; uma decisão diferente cria outro. `writer_status` muda por `update_all` com condição (a
# reivindicação da escrita), não por estas validações.
class Crm::MetaAdvisorRun < ApplicationRecord
  self.table_name = 'crm_meta_advisor_runs'

  TRIGGERS = %w[panel digest].freeze
  WRITER_STATUSES = %w[pending writing written rule].freeze

  belongs_to :account
  has_many :actions, class_name: 'Crm::MetaAdvisorAction', foreign_key: :run_id, inverse_of: :run, dependent: :nullify

  validates :ad_account_id, :local_date, :locale, :signature, :rules_version, presence: true
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :writer_status, inclusion: { in: WRITER_STATUSES }
end
