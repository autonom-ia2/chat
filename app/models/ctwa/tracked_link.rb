# == Schema Information
#
# Table name: ctwa_tracked_links
#
#  id                  :bigint           not null, primary key
#  allowed_origins     :jsonb            not null
#  clicks_count        :integer          default(0), not null
#  code                :string           not null
#  conversations_count :integer          default(0), not null
#  last_signal_at      :datetime
#  name                :string           not null
#  prefilled_text      :string           default("")
#  usage               :string           default("direct"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  created_by_id       :bigint
#  inbox_id            :bigint           not null
#
# Indexes
#
#  idx_ctwa_tracked_links_account  (account_id)
#  idx_ctwa_tracked_links_code     (code) UNIQUE
#  idx_ctwa_tracked_links_inbox    (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
require 'cgi'

class Ctwa::TrackedLink < ApplicationRecord
  self.table_name = 'ctwa_tracked_links'

  CODE_ALPHABET = (('A'..'Z').to_a - %w[I O] + ('2'..'9').to_a).freeze
  CODE_FORMAT = /\A[A-Z2-9]{6}\z/
  # direct: QR code / link curto (/l/:code redireciona ao WhatsApp).
  # website: botão de uma página que avisa o clique em paralelo (POST /l/:code/clicks, #1011).
  USAGES = %w[direct website].freeze
  MAX_ALLOWED_ORIGINS = 5
  LOCALHOST = 'localhost'.freeze
  SIGNALS_DAILY_LIMIT = ENV.fetch('TRACKED_LINK_SIGNALS_DAILY_LIMIT_PER_LINK', '5000').to_i

  belongs_to :account
  belongs_to :inbox

  before_validation :generate_code, on: :create
  before_validation :normalize_allowed_origins

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true, format: { with: CODE_FORMAT }
  validates :usage, inclusion: { in: USAGES }
  validate :inbox_must_be_whatsapp
  validate :allowed_origins_must_be_valid
  validate :usage_cannot_change, on: :update

  scope :for_account, ->(account) { where(account_id: account.id) }

  # `scheme://host[:port]` em minúsculas, sem barra final, ou nil quando não é uma origem.
  # Porta padrão (80/443) é omitida, como o navegador faz no header Origin.
  def self.normalize_origin(value)
    uri = origin_uri(value)
    return if uri.blank?

    origin = "#{uri.scheme.downcase}://#{uri.host.downcase}"
    uri.port == uri.default_port ? origin : "#{origin}:#{uri.port}"
  end

  # Só scheme + host (+ porta): sem usuário, caminho, query ou fragmento.
  def self.origin_uri(value)
    return unless value.is_a?(String)

    uri = URI.parse(value.strip)
    uri if web_host?(uri) && [uri.userinfo, uri.query, uri.fragment].all?(&:blank?) && ['', '/'].include?(uri.path.to_s)
  rescue URI::Error
    nil
  end

  def self.web_host?(uri)
    %w[http https].include?(uri.scheme.to_s.downcase) && uri.host.present?
  end

  # Usado pelo Rack::Cors no preflight de POST /l/:code/clicks (config/initializers/cors.rb):
  # o middleware responde todo preflight antes do Rails, então a regra de origem do link
  # precisa valer também ali. O Rack::Cors chama isto para TODA requisição com Origin
  # (antes de olhar o caminho), então o caminho é conferido primeiro, sem consulta.
  def self.signal_origin_allowed?(path, origin)
    code = signal_code_from_path(path)
    return false if code.nil?

    link = find_by(code: code)
    link.present? && link.website? && link.origin_allowed?(origin)
  end

  # Código do link em `/l/:code/clicks` (em maiúsculas), ou nil para qualquer outro caminho.
  # Sem consulta: roda no Rack::Attack, antes do Rails.
  # O caminho é lido como o roteador lê (`//l//X/clicks/` chega no mesmo controller, e
  # `%41` no código vira `A`): toda grafia que o Rails entrega ao endpoint cai na mesma
  # conta do limite.
  def self.signal_code_from_path(path)
    parts = public_path_parts(path)
    return unless parts.size == 4 && parts[1] == 'l' && parts[3] == 'clicks'

    code = ActionDispatch::Journey::Router::Utils.unescape_uri(parts[2]).scrub
    code.upcase unless code.empty?
  end

  # Qualquer caminho sob `/l/`, lido como o roteador lê. Usado pelo
  # Middleware::TrackedLinkSignalGuard: nenhum POST ali tem corpo que o Rails deva interpretar,
  # nem quando a grafia não chega ao endpoint (`.json` vira 404, e a página de erro lê o corpo).
  def self.public_path?(path)
    public_path_parts(path)[1] == 'l'
  end

  def self.public_path_parts(path)
    ActionDispatch::Journey::Router::Utils.normalize_path(path.to_s).split('/')
  end
  private_class_method :public_path_parts

  def website?
    usage == 'website'
  end

  # Teto de avisos aceitos por link em 24h (CA-1.11). Acima dele o endpoint responde 429 e a
  # tela mostra o bloqueio (signals_blocked), para não perder atribuição em silêncio.
  def signals_daily_limit_reached?
    Ctwa::TrackedLinkClick.where(tracked_link_id: id).where('created_at > ?', 24.hours.ago).count >= SIGNALS_DAILY_LIMIT
  end

  def origin_allowed?(origin)
    normalized = self.class.normalize_origin(origin)
    normalized.present? && Array(allowed_origins).include?(normalized)
  end

  def wa_link
    phone = inbox&.channel.try(:phone_number).to_s.delete('+')
    return if phone.blank?

    text = CGI.escape("#{prefilled_text} ##{code}")

    "https://wa.me/#{phone}?text=#{text}"
  end

  private

  # Public /l/:code redirects to wa.me, which only exists for WhatsApp channels —
  # any other inbox type would create a dead link (and a nil phone_number crash).
  def inbox_must_be_whatsapp
    return if inbox.blank? || inbox.channel.is_a?(Channel::Whatsapp)

    errors.add(:inbox, 'must be a WhatsApp inbox')
  end

  def normalize_allowed_origins
    return unless allowed_origins.is_a?(Array)

    self.allowed_origins = allowed_origins.map { |origin| self.class.normalize_origin(origin) || origin }.uniq
  end

  def allowed_origins_must_be_valid
    return errors.add(:allowed_origins, 'must be a list') unless allowed_origins.is_a?(Array)
    return errors.add(:allowed_origins, "accepts at most #{MAX_ALLOWED_ORIGINS} origins") if allowed_origins.size > MAX_ALLOWED_ORIGINS

    invalid = allowed_origins.reject { |origin| acceptable_origin?(origin) }
    errors.add(:allowed_origins, "invalid origin: #{invalid.first.to_s.first(80)}") if invalid.any?
  end

  # https sempre; http só para localhost e só fora de produção (teste local da página).
  def acceptable_origin?(origin)
    normalized = self.class.normalize_origin(origin)
    return false if normalized.blank? || normalized != origin
    return true if normalized.start_with?('https://')

    !Rails.env.production? && URI.parse(normalized).host == LOCALHOST
  end

  def usage_cannot_change
    errors.add(:usage, 'cannot be changed') if will_save_change_to_usage?
  end

  def generate_code
    return if code.present?

    loop do
      self.code = Array.new(6) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)] }.join
      break unless self.class.exists?(code: code)
    end
  end
end
