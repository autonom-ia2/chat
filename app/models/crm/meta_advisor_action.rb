# Uma ação que o consultor de anúncios da Meta recomendou num dia (#1110, F5) e o que a pessoa fez com ela.
# Uma linha por conta · dia · tipo · assunto (`account` ou `ad:<ad_id>`): o run seguinte do mesmo dia atualiza
# fatos, variante e posição, mas nunca o status. Os fillers (`wait`, `on_track`, `no_data`) não viram linha.
#
# O PRD separa "quem abriu" de "quem aceitou" (D5.9): o botão principal só grava `opened_*`; aceitar e
# dispensar são gestos explícitos e só valem enquanto a ação está aberta. `*_via` diz se o gesto veio do painel
# ou do Guia (`api`); a métrica de aceite conta só o painel (D5.11).
class Crm::MetaAdvisorAction < ApplicationRecord
  self.table_name = 'crm_meta_advisor_actions'

  # Aceitar ou dispensar uma ação que já foi aceita, dispensada ou venceu (o controller responde 422 `not_open`).
  class NotOpen < StandardError; end

  KINDS = %w[stalled_quotes slow_response fix_tracking review_ad refresh_creative scale_ad auction_pressure].freeze
  VIAS = %w[panel api].freeze

  belongs_to :account
  belongs_to :run, class_name: 'Crm::MetaAdvisorRun', optional: true, inverse_of: :actions
  belongs_to :opened_by, class_name: 'User', optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  # `expired`: o dia acabou sem resposta (Analysis marca ao criar o primeiro run do dia seguinte).
  enum :status, { open: 0, accepted: 1, dismissed: 2, expired: 3 }

  validates :local_date, :subject_key, :position, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :opened_via, :resolved_via, inclusion: { in: VIAS }, allow_nil: true

  # A meta do PRD ("aceita ≥ 4 de 5"), a mesma conta da SQL do desenho (docs/crm/anuncios-meta-f5.md §3): só as
  # ações mostradas no período; as respondidas pelo Guia ficam fora; as abertas e vencidas contam como sem
  # resposta. `rate` é nil sem nenhuma ação no denominador.
  def self.acceptance(account_id, from:, to:)
    shown, opened, accepted, dismissed, unanswered =
      where(account_id: account_id, local_date: from..to, resolved_via: [nil, 'panel'])
      .where.not(shown_at: nil)
      .pick(*acceptance_columns)
    answered_or_not = accepted + dismissed + unanswered

    { shown: shown, opened: opened, accepted: accepted, dismissed: dismissed, unanswered: unanswered,
      rate: answered_or_not.zero? ? nil : accepted.fdiv(answered_or_not) }
  end

  def self.acceptance_columns
    [
      'count(*)',
      'count(*) filter (where opened_at is not null)',
      "count(*) filter (where status = #{statuses[:accepted]})",
      "count(*) filter (where status = #{statuses[:dismissed]})",
      "count(*) filter (where status in (#{statuses[:open]}, #{statuses[:expired]}))"
    ].map { |sql| Arel.sql(sql) }
  end
  private_class_method :acceptance_columns

  # Primeiro clique no botão principal. Idempotente e vale em qualquer status: não muda o status. Substitui o
  # `open!` que o enum criaria (voltar o status para `open`), que nenhum fluxo usa.
  def open!(user, via:)
    with_lock do
      update!(opened_at: Time.current, opened_by: user, opened_via: via) if opened_at.nil?
    end
    self
  end

  def accept!(user, via:)
    resolve!(:accepted, user, via)
  end

  def dismiss!(user, via:)
    resolve!(:dismissed, user, via)
  end

  private

  # O lock relê a linha: duas abas (ou "Feito" e "Dispensar" juntos) não resolvem a mesma ação duas vezes.
  def resolve!(new_status, user, via)
    with_lock do
      raise NotOpen unless open?

      update!(status: new_status, resolved_at: Time.current, resolved_by: user, resolved_via: via)
    end
    self
  end
end
