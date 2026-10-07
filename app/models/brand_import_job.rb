# Importação da identidade visual de um site (#1076). `result` guarda a proposta extraída — nunca HTML
# ou CSS bruto. Uma importação ativa (na fila ou rodando) por conta, garantida por índice parcial.
class BrandImportJob < ApplicationRecord
  # Limit of the import screen (Identidade visual, "Usar outro site").
  HOURLY_LIMIT = 10
  # Sites read because a request of Criar/Ajustar com IA named one (#1111): marked in result['origin'], kept out of
  # the screen's limit and capped on their own.
  ORIGIN_BRIEFING = 'briefing'.freeze
  BRIEFING_HOURLY_LIMIT = 30
  # Passado esse tempo, uma importação ativa é dada como perdida (worker reiniciado no meio).
  STALE_AFTER = 3.minutes

  belongs_to :account
  belongs_to :user, optional: true

  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 3 }

  validates :url, presence: true, length: { maximum: BrandKits::WebAddress::MAX_LENGTH }

  scope :active, -> { where(status: %i[queued running]) }
  scope :from_briefing, -> { where("result ->> 'origin' = ?", ORIGIN_BRIEFING) }
  scope :from_import_screen, -> { where("COALESCE(result ->> 'origin', '') <> ?", ORIGIN_BRIEFING) }
  scope :last_hour, -> { where('created_at > ?', 1.hour.ago) }

  def stale?
    (queued? || running?) && (started_at || created_at) < STALE_AFTER.ago
  end

  def fail!(code)
    update!(status: :failed, error_code: code, finished_at: Time.current)
  end
end
