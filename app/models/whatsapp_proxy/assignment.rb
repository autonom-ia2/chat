# IP da Webshare de uma sessão do motor de WhatsApp não oficial (#1516). Um IP pertence a uma conta só e leva até
# WHATSAPP_PROXY_MAX_NUMBERS_PER_IP números dela. Só endereço e porta: a credencial vem da API na hora de configurar a
# sessão e nunca é gravada.
# - Pendente (endereço vazio): a caixa nasceu sem proxy porque a Webshare estava fora; a reconciliação tenta de novo.
# - `previous_*`: o IP de antes da última troca, para voltar a ele se o motor recusar a troca.
# - Recuo: cada troca desfeita conta; a próxima tentativa só depois de BACKOFF[falhas - 1] (máx. 24 h).
class WhatsappProxy::Assignment < ApplicationRecord
  self.table_name = 'whatsapp_proxy_assignments'

  POOLS = %w[isp datacenter].freeze
  ORIGINS = %w[assigned imported].freeze
  DEFAULT_MAX_NUMBERS_PER_IP = 3
  LOCK_KEY = 1_516_000_001
  BACKOFF = [10.minutes, 30.minutes, 2.hours, 6.hours, 24.hours].freeze

  belongs_to :account

  validates :session_name, presence: true, uniqueness: true
  validates :pool, inclusion: { in: POOLS }
  validates :origin, inclusion: { in: ORIGINS }
  validates :proxy_port, numericality: { only_integer: true, greater_than: 0 }, if: :proxy_address?
  validates :proxy_port, absence: true, unless: :proxy_address?
  validates :assigned_at, presence: true
  validate :one_account_per_ip, if: :proxy_address?
  validate :numbers_per_ip_within_limit, if: :proxy_address?

  # Atribuições que o código cuida: as da Webshare e as pendentes (sem endereço).
  scope :managed, -> { where.not(webshare_proxy_id: nil).or(where(proxy_address: nil)) }

  def self.max_numbers_per_ip
    value = ENV.fetch('WHATSAPP_PROXY_MAX_NUMBERS_PER_IP', '').to_i
    value.positive? ? value : DEFAULT_MAX_NUMBERS_PER_IP
  end

  # Toda escrita de atribuição (Assigner e importação) roda sob esta trava: duas contas nunca pegam o mesmo IP.
  def self.exclusively(&)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      yield
    end
  end

  # Número já movido à mão (importado): só troca de plano/conta com WHATSAPP_PROXY_AUTO_MIGRATE=true.
  def self.auto_migrate?
    ENV.fetch('WHATSAPP_PROXY_AUTO_MIGRATE', 'false') == 'true'
  end

  def self.sharing_ip(address, except_session:)
    where(proxy_address: address).where.not(session_name: except_session)
  end

  def server
    "#{proxy_address}:#{proxy_port}" if proxy_address?
  end

  def pending?
    proxy_address.blank?
  end

  # Proxy posto à mão fora da Webshare: fica reservado, mas o código não tem a credencial para regravá-lo.
  def external?
    webshare_proxy_id.blank? && !pending?
  end

  def imported?
    origin == 'imported'
  end

  # Plano ou conta não batem com a sessão e o número pode ser movido automaticamente.
  def migratable_to?(owner)
    mismatch = pool != owner.pool || account_id != owner.account_id
    mismatch && (!imported? || self.class.auto_migrate?)
  end

  def in_backoff?
    apply_failures.positive? && last_apply_failed_at.present? &&
      last_apply_failed_at + BACKOFF[[apply_failures, BACKOFF.size].min - 1] > Time.current
  end

  def backoff_exhausted?
    apply_failures >= BACKOFF.size
  end

  # A troca foi para o motor: zera o recuo e esquece o IP anterior.
  def applied!(credential_digest)
    update!(credential_digest: credential_digest, apply_failures: 0, last_apply_failed_at: nil,
            previous_proxy_address: nil, previous_proxy_port: nil, previous_webshare_proxy_id: nil, previous_credential_digest: nil)
  end

  # O motor recusou a troca e a configuração anterior voltou: a atribuição volta junto (ou fica pendente, se não havia
  # IP antes) e conta mais uma falha para o recuo.
  def revert_failed_apply!
    update!(proxy_address: previous_proxy_address, proxy_port: previous_proxy_port, webshare_proxy_id: previous_webshare_proxy_id,
            credential_digest: previous_credential_digest, previous_proxy_address: nil, previous_proxy_port: nil,
            previous_webshare_proxy_id: nil, previous_credential_digest: nil,
            apply_failures: apply_failures + 1, last_apply_failed_at: Time.current)
  end

  def apply_failed!
    update!(apply_failures: apply_failures + 1, last_apply_failed_at: Time.current)
  end

  private

  def one_account_per_ip
    return unless self.class.sharing_ip(proxy_address, except_session: session_name).where.not(account_id: account_id).exists?

    errors.add(:proxy_address, 'já é de outra conta')
  end

  def numbers_per_ip_within_limit
    return if self.class.sharing_ip(proxy_address, except_session: session_name).count < self.class.max_numbers_per_ip

    errors.add(:proxy_address, "já tem #{self.class.max_numbers_per_ip} números")
  end
end
