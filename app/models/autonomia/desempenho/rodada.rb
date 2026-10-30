# Uma rodada da leitura automática diária do painel de desempenho (#2301): até onde leu (`corte_em`), como terminou
# e quanto gastou. O painel lê daqui o "Lido até" (corte da última rodada que leu) e a situação da leitura
# (`sem_ia`, `chave_recusada`, `teto` ou `erro` quando a última rodada parou por isso).
class Autonomia::Desempenho::Rodada < ApplicationRecord
  self.table_name = 'autonomia_desempenho_rodadas'

  include Autonomia::Desempenho::Sujeito

  STATUS = %w[rodando ok teto sem_ia chave_recusada erro].freeze
  PARADAS = %w[sem_ia chave_recusada teto erro].freeze

  validates :status, inclusion: { in: STATUS }
  validates :corte_em, :piso_em, :iniciada_em, presence: true
  validates :conversas_lidas, :conversas_pendentes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recentes, -> { order(iniciada_em: :desc, id: :desc) }
  # As que leram de verdade, e o "Lido até" sai delas: a `ok` e a que parou (`teto`, `erro`, `chave_recusada`) depois
  # de ler alguma conversa; a pendente dela fica em `pendente_desde`. A que parou antes da primeira não leu nada (a
  # `erro` de RodadaComErro nem conta as lidas).
  scope :leram, -> { where(status: 'ok').or(where(status: %w[teto erro chave_recusada], conversas_lidas: 1..)) }

  # A rodada que ficou `rodando` porque o processo foi interrompido no meio (deploy: o Sidekiq::Shutdown não é
  # StandardError) fecha como `erro`, para não ficar `rodando` para sempre. Roda no `ensure` do orquestrador: não
  # levanta, só loga. Confere o status do banco, não o da memória: um `update!` que falhou deixa o novo status só aqui.
  def interrompida!
    return unless status_in_database == 'rodando'

    update_columns(status: 'erro', terminada_em: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error("[desempenho][leitura] conta=#{account_id} rodada=#{id} interrompida=#{e.class.name}")
  end
end
