# == Schema Information
#
# Table name: ctwa_tracked_link_clicks
#
#  id              :bigint           not null, primary key
#  campaign_key    :string
#  expires_at      :datetime         not null
#  lead_data       :jsonb            not null
#  meta_signals    :jsonb            not null
#  page_url        :string(512)
#  params          :jsonb            not null
#  token           :string           not null
#  user_agent      :string(255)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint
#  tracked_link_id :bigint           not null
#
# Indexes
#
#  idx_ctwa_tracked_link_clicks_account       (account_id)
#  idx_ctwa_tracked_link_clicks_conversation  (conversation_id)
#  idx_ctwa_tracked_link_clicks_link_campaign  (tracked_link_id,campaign_key)
#  idx_ctwa_tracked_link_clicks_link          (tracked_link_id)
#  idx_ctwa_tracked_link_clicks_link_created  (tracked_link_id,created_at)
#  idx_ctwa_tracked_link_clicks_token         (token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (tracked_link_id => ctwa_tracked_links.id) ON DELETE => cascade
#
class Ctwa::TrackedLinkClick < ApplicationRecord
  self.table_name = 'ctwa_tracked_link_clicks'

  TOKEN_FORMAT = /\A[A-Z2-9]{8}\z/
  TRACKING_PARAM_KEYS = %w[
    gclid
    fbclid
    ttclid
    utm_source
    utm_medium
    utm_campaign
    utm_term
    utm_content
    utm_id
  ].freeze
  NO_CAMPAIGN_KEY = 'none'.freeze
  CAMPAIGN_DIGEST_LENGTH = 10
  # Id de campanha da Meta: só dígitos e curto. Fora disso o utm_id vira resumo, porque a chave
  # entra no source_id do toque e no filtro de campanha do CRM (lista separada por vírgula).
  MAX_RAW_CAMPAIGN_ID_LENGTH = 32
  DIGITS = ('0'..'9').to_a.freeze
  PAGE_URL_MAX_LENGTH = 512
  # Dado pessoal do clique (formulário e sinais da Meta), apagado quando perde a finalidade.
  PERSONAL_DATA_RESET = { lead_data: {}, meta_signals: {}, user_agent: nil }.freeze

  belongs_to :account
  belongs_to :tracked_link, class_name: 'Ctwa::TrackedLink'
  belongs_to :conversation, optional: true

  before_validation :generate_token, on: :create
  before_validation :set_expires_at, on: :create
  before_validation :normalize_params
  # prepend: ApplicationRecord's generic validates_column_content_length runs earlier in the
  # chain and would flag the untruncated value before this callback shortens it.
  before_validation :truncate_user_agent, prepend: true

  validates :token, presence: true, uniqueness: true, format: { with: TOKEN_FORMAT }
  validates :expires_at, presence: true
  # Validador próprio: desliga o limite genérico de 255 do ApplicationRecord (a coluna é 512).
  validates :page_url, length: { maximum: PAGE_URL_MAX_LENGTH }
  validate :params_must_be_hash

  scope :active, -> { where(conversation_id: nil).where('expires_at > ?', Time.current) }

  # Chave estável da campanha de um clique de página (#1011): o id da campanha da Meta
  # (utm_id só com dígitos) quando vem; outro utm_id vira `i:` + resumo; sem utm_id, um
  # resumo do nome (utm_campaign); `none` sem campanha.
  def self.campaign_key_for(params)
    tracking = params.to_h.stringify_keys
    return campaign_id_key(tracking['utm_id']) if tracking['utm_id'].present?
    return NO_CAMPAIGN_KEY if tracking['utm_campaign'].blank?

    "c:#{campaign_digest(tracking['utm_campaign'])}"
  end

  def self.campaign_id_key(utm_id)
    raw = utm_id.to_s
    return raw if raw.size <= MAX_RAW_CAMPAIGN_ID_LENGTH && raw.each_char.all? { |char| DIGITS.include?(char) }

    "i:#{campaign_digest(raw)}"
  end

  def self.campaign_digest(value)
    Digest::SHA1.hexdigest(value)[0, CAMPAIGN_DIGEST_LENGTH]
  end
  private_class_method :campaign_id_key, :campaign_digest

  private

  def generate_token
    return if token.present?

    alphabet = Ctwa::TrackedLink::CODE_ALPHABET
    loop do
      self.token = Array.new(8) { alphabet[SecureRandom.random_number(alphabet.length)] }.join
      break unless self.class.exists?(token: token)
    end
  end

  def set_expires_at
    self.expires_at ||= 72.hours.from_now
  end

  def normalize_params
    return if params.blank?
    return unless params.respond_to?(:to_h)

    self.params = params.to_h.stringify_keys.slice(*TRACKING_PARAM_KEYS).each_with_object({}) do |(key, value), normalized|
      next unless value.is_a?(String)
      next if value.blank?

      normalized[key] = value.first(512)
    end
  end

  def truncate_user_agent
    return if user_agent.blank?

    self.user_agent = user_agent.first(255)
  end

  def params_must_be_hash
    return if params.is_a?(Hash)

    errors.add(:params, 'must be a hash')
  end
end
