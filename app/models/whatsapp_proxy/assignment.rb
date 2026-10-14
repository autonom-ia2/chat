# IP da Webshare de uma sessão do motor de WhatsApp não oficial (#1516). Um IP pertence a uma conta só e leva até
# WHATSAPP_PROXY_MAX_NUMBERS_PER_IP números dela. Só endereço e porta: a credencial vem da API na hora de configurar a
# sessão e nunca é gravada.
# - Pendente (endereço vazio): a caixa nasceu sem proxy porque a Webshare estava fora; a reconciliação tenta de novo.
# - `previous_*`: o estado de antes da última troca ainda não confirmada (IP, plano, conta, origem). A troca é gravada
#   já nos campos principais (o IP novo fica reservado para este número desde a escolha) e o anterior fica guardado;
#   confirmada, ele é esquecido; desfeita, tudo volta. Escolhido em vez de colunas `target_*` porque toda a leitura
#   (escolha de IP livre, contagem por IP, falha geral) já usa os campos principais — com `target_*` cada uma teria de
#   olhar os dois lugares. Enquanto isso o IP antigo continua protegido: o motor ainda o mostra nesta sessão, e IP em
#   uso no motor nunca é oferecido a outra conta.
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
  validate :numbers_per_ip_within_limit, if: -> { proxy_address? && will_save_change_to_proxy_address? }

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

  PREVIOUS = { proxy_address: :previous_proxy_address, proxy_port: :previous_proxy_port,
               webshare_proxy_id: :previous_webshare_proxy_id, credential_digest: :previous_credential_digest,
               pool: :previous_pool, account_id: :previous_account_id, origin: :previous_origin }.freeze
  FORGET_PREVIOUS = PREVIOUS.values.index_with { nil }.freeze

  def awaiting_confirmation?
    previous_pool.present?
  end

  # Estado atual guardado antes de uma troca (só a primeira vez: troca ainda não confirmada mantém o original).
  def previous_attributes
    return {} if awaiting_confirmation?

    PREVIOUS.to_h { |field, previous| [previous, self[field]] }
  end

  IN_FLIGHT = 30.minutes

  # Troca agendada há pouco e ainda sem desfecho: a convergência com o motor espera (a divergência é esperada).
  def in_flight?
    apply_scheduled_at.present? && apply_scheduled_at > IN_FLIGHT.ago
  end

  def scheduled!
    update!(apply_scheduled_at: Time.current)
  end

  # A troca foi para o motor e foi conferida: zera o recuo e esquece o estado anterior.
  def applied!(credential_digest)
    update!(settled.merge(credential_digest: credential_digest, apply_failures: 0, last_apply_failed_at: nil))
  end

  # O motor já estava com este proxy (sem PUT): registra a credencial; o recuo só zera se já tinha vencido.
  def confirmed!(credential_digest)
    reset = in_backoff? ? {} : { apply_failures: 0, last_apply_failed_at: nil }
    update!(settled.merge(reset).merge(credential_digest: credential_digest))
  end

  # O motor recusou a troca e a configuração anterior voltou: a atribuição volta inteira (IP, plano, conta, origem — ou
  # fica pendente, se não havia IP antes) e conta mais uma falha para o recuo.
  def revert_failed_apply!(credential_digest: previous_credential_digest)
    restored = PREVIOUS.transform_values { |previous| self[previous] }
    restored = restored.merge(pool: pool, account_id: account_id, origin: origin) unless awaiting_confirmation?
    update!(restored.merge(settled).merge(credential_digest: credential_digest, apply_failures: apply_failures + 1,
                                          last_apply_failed_at: Time.current))
  end

  # A volta da configuração anterior falhou. O motor é a fonte da verdade (#1516): com o que ele mostra relido,
  # a tabela fica igual a ele — no IP novo, no anterior, ou (motor ilegível / outro proxy) sem credencial e com o
  # anterior guardado, para a convergência da reconciliação resolver na próxima rodada.
  def rollback_failed!(engine_server:, engine_digest:)
    if WhatsappProxy::Server.same?(engine_server, server)
      update!(settled.merge(credential_digest: engine_digest).merge(failure))
    elsif awaiting_confirmation? && WhatsappProxy::Server.same?(engine_server, "#{previous_proxy_address}:#{previous_proxy_port}")
      revert_failed_apply!(credential_digest: engine_digest)
    else
      update!(failure.merge(credential_digest: nil, apply_scheduled_at: nil))
    end
  end

  # O motor usa um proxy válido da conta e do plano diferente do da tabela: a tabela passa a ser ele (sem PUT).
  def adopt!(proxy, credential_digest, owner)
    update!(settled.merge(proxy_address: proxy.address, proxy_port: proxy.port, webshare_proxy_id: proxy.id,
                          credential_digest: credential_digest, pool: owner.pool, account_id: owner.account_id))
  end

  def failure
    { apply_failures: apply_failures + 1, last_apply_failed_at: Time.current }
  end

  def settled
    FORGET_PREVIOUS.merge(apply_scheduled_at: nil)
  end

  def apply_failed!
    update!(failure.merge(apply_scheduled_at: nil))
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
