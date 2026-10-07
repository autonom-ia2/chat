# Importação da identidade visual de um site (#1076). `result` guarda a proposta extraída — nunca HTML
# ou CSS bruto. Uma importação ativa (na fila ou rodando) por conta, garantida por índice parcial.
class BrandImportJob < ApplicationRecord
  HOURLY_LIMIT = 10
  # Passado esse tempo, uma importação ativa é dada como perdida (worker reiniciado no meio).
  STALE_AFTER = 3.minutes

  belongs_to :account
  belongs_to :user, optional: true

  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 3 }

  validates :url, presence: true, length: { maximum: BrandKits::WebAddress::MAX_LENGTH }

  scope :active, -> { where(status: %i[queued running]) }

  def stale?
    (queued? || running?) && (started_at || created_at) < STALE_AFTER.ago
  end

  def fail!(code)
    update!(status: :failed, error_code: code, finished_at: Time.current)
  end
end
