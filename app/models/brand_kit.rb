# Kit de marca da conta (#1076): paleta com papéis, fontes, logo, redes e rodapé que o e-mail com IA usa.
# Tabela do fork. Um padrão por conta entre os não arquivados (índice parcial); arquivar tira da lista,
# não apaga, e libera o nome.
class BrandKit < ApplicationRecord
  class ArchivedError < StandardError; end

  LOGO_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  LOGO_MAX_BYTES = 5.megabytes
  NAME_MAX = 80

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_one_attached :logo

  scope :live, -> { where(archived_at: nil) }

  before_validation :normalize_fields
  validates :name, presence: true, length: { maximum: NAME_MAX }
  validates :name, uniqueness: { scope: :account_id, case_sensitive: false, conditions: -> { live } }, unless: :archived?
  validates :source_url, length: { maximum: BrandKits::WebAddress::MAX_LENGTH }, allow_nil: true
  validate :source_url_is_web_address
  validate :appearance_follows_schema
  validate :logo_is_raster_image

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current, is_default: false)
  end

  def make_default!
    raise ArchivedError if archived?

    transaction do
      # Serializa trocas de padrão da mesma conta: sem a trava, duas chamadas simultâneas
      # desmarcam o padrão atual e a segunda bate no índice único (500 em vez de vencer a última).
      Account.where(id: account_id).lock.pick(:id)
      self.class.where(account_id: account_id, is_default: true).where.not(id: id).find_each { |kit| kit.update!(is_default: false) }
      update!(is_default: true)
    end
  end

  # Leitura tolerante do jsonb: chaves que um formato futuro gravou não chegam a quem lê.
  def appearance_data
    BrandKits::Appearance.new(appearance).to_h
  end

  private

  def normalize_fields
    self.name = name.to_s.strip.presence
    self.source_url = source_url.to_s.strip.presence
    self.appearance = BrandKits::Appearance.new(appearance).to_h
  end

  def source_url_is_web_address
    errors.add(:source_url, :invalid) if source_url.present? && !BrandKits::WebAddress.http?(source_url)
  end

  def appearance_follows_schema
    BrandKits::Appearance.new(appearance).errors.each { |field| errors.add(:appearance, :invalid_field, field: field) }
  end

  def logo_is_raster_image
    return unless logo.attached?

    errors.add(:logo, :invalid_type) unless LOGO_CONTENT_TYPES.include?(logo.blob.content_type)
    errors.add(:logo, :too_large) if logo.blob.byte_size > LOGO_MAX_BYTES
  end
end
