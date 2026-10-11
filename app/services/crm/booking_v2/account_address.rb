# Endereço da conta no link de agendamento (#1299): o `<conta>` de `/a/<conta>/<página>`. Um por conta, único na
# instalação inteira, no mesmo formato do nome da página (`Crm::BookingV2::ShortName`). Fica em tabela própria
# (`crm_booking_account_addresses`): os índices únicos do banco garantem um endereço por conta e um dono por endereço.
#
# Nasce sozinho, a partir do nome da conta e com número quando o nome já tem dono, em dois lugares: quando uma página
# nova da conta é gravada (criar, salvar, publicar) e no preenchimento do deploy (`ShortNameBackfill`).
# Leitura não cria endereço: conta sem endereço numa leitura segue com o link comprido. Ainda não há tela para trocar.
#
# Um endereço de conta não pode ser igual ao nome de página de OUTRA conta: o link antigo `/a/<página>` (#1282)
# continua abrindo enquanto o nome for de uma página só, e um endereço de conta igual passaria na frente dele. O
# contrário pode, de propósito: a página com nome igual ao endereço de outra conta abre pelo endereço da própria conta,
# e o endereço alheio nunca a alcança (`ShortLink.resolve` fica dentro da conta do primeiro pedaço). Barrar esse nome
# faria a conferência do painel revelar endereços de outras contas.
class Crm::BookingV2::AccountAddress
  CREATE_TRIES = 5

  def self.name_for(account)
    name_for_id(account.id)
  end

  def self.name_for_id(account_id)
    ::Crm::BookingAccountAddress.where(account_id: account_id).pick(:name)
  end

  # O endereço da conta, criando se ainda não existe. Pode ser chamado quantas vezes for: os índices únicos garantem
  # uma linha por conta e um dono por nome.
  # - Duas gravações da MESMA conta ao mesmo tempo: a segunda bate no índice de `account_id`, e a nova volta relê o
  #   endereço que a primeira gravou.
  # - Duas contas disputando o MESMO nome: a segunda bate no índice de `name`, e a nova volta sugere o próximo número.
  def self.ensure!(account)
    CREATE_TRIES.times do
      name = name_for(account) || create(account)
      return name if name
    end
    raise ActiveRecord::RecordNotUnique, "endereço de agendamento da conta #{account.id}: #{CREATE_TRIES} tentativas"
  end

  # A conta dona do endereço, ou nil.
  def self.find_account(value)
    name = ::Crm::BookingV2::ShortName.normalize(value)
    return if name.nil? || ::Crm::BookingV2::ShortName.format_problem(name)

    ::Crm::BookingAccountAddress.includes(:account).find_by(name: name)&.account
  end

  # O que impede a conta de ter este endereço (ou nil).
  def self.problem(value, account_id:)
    name = ::Crm::BookingV2::ShortName.normalize(value)
    ::Crm::BookingV2::ShortName.format_problem(name) || ('taken' if taken?(name, account_id: account_id))
  end

  def self.taken?(name, account_id:)
    ::Crm::BookingAccountAddress.where(name: name).where.not(account_id: account_id).exists? ||
      ::Crm::AgentBookingProfile.where(short_name: name).where.not(account_id: account_id).exists?
  end

  def self.suggest(account)
    ::Crm::BookingV2::ShortName.free_name(account.name) { |name| taken?(name, account_id: account.id) }
  end

  # Em transação própria (savepoint): o erro do índice desfaz só esta tentativa e não envenena a transação de quem
  # chamou. A validação pega a mesma disputa quando a outra gravação já terminou (`RecordInvalid`).
  def self.create(account)
    ::Crm::BookingAccountAddress.transaction(requires_new: true) do
      ::Crm::BookingAccountAddress.create!(account_id: account.id, name: suggest(account)).name
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
  private_class_method :create
end
