# Dá endereço curto às páginas de agendamento que nasceram antes dele (#1299): depois do deploy, toda página nova
# (page_version 2) abre em `/a/<conta>/<página>` sem ninguém precisar abrir em Editar. Roda pela migration
# `BackfillBookingShortNames`.
#
# Por conta que tem página nova, numa transação só dela:
# - cria o endereço da conta, se ainda não existe (`AccountAddress.ensure!`, a partir do nome da conta);
# - para cada página SEM nome, grava um nome a partir do título, único na conta (`ShortName.suggest`);
# - dá apelido às pessoas dessas páginas que ainda não têm (`PersonNames`).
#
# Página que já tem nome não é tocada e conta que já tem endereço não ganha outro, então rodar de novo não muda nada.
# Só a coluna `short_name` é gravada (`update_all` na própria página, e só se ela continua sem nome): uma página
# antiga que hoje não passaria em outra validação não pode ficar sem endereço, e o `updated_at` da página fica como
# estava (o do link que ganha apelido muda). Conta que falha é desfeita sozinha, registrada no log e não para as outras.
class Crm::BookingV2::ShortNameBackfill
  # `accounts`: contas em que algo foi gravado; `pages`: páginas que ganharam nome.
  Result = Struct.new(:accounts, :pages, :failed_account_ids)
  # Uma trava ou impasse com uma gravação do painel no mesmo instante desfaz a conta inteira; ela tenta mais uma vez.
  ATTEMPTS = 2

  def self.run
    new.run
  end

  def run
    result = Result.new(0, 0, [])
    ::Account.where(id: ::Crm::AgentBookingProfile.new_pages.select(:account_id)).find_each do |account|
      address_created, pages = backfill_with_retry(account)
      result.pages += pages
      result.accounts += 1 if address_created || pages.positive?
    rescue StandardError => e
      Rails.logger.error("[booking_short_name_backfill] conta #{account.id}: #{e.class}: #{e.message}")
      result.failed_account_ids << account.id
    end
    result
  end

  private

  def backfill_with_retry(account)
    tries = 0
    begin
      tries += 1
      backfill(account)
    rescue ActiveRecord::TransactionRollbackError, ActiveRecord::LockWaitTimeout
      retry if tries < ATTEMPTS
      raise
    end
  end

  def backfill(account)
    ::Crm::AgentBookingProfile.transaction do
      address_created = ::Crm::BookingV2::AccountAddress.name_for(account).nil?
      ::Crm::BookingV2::AccountAddress.ensure!(account)
      [address_created, unnamed.where(account_id: account.id).order(:id).to_a.count { |page| name!(page) }]
    end
  end

  def unnamed
    ::Crm::AgentBookingProfile.new_pages.where(short_name: [nil, ''])
  end

  # Grava só se a página continua sem nome: com o sistema no ar, alguém pode ter salvo um endereço nela entre a
  # leitura e esta gravação, e o nome que a pessoa escolheu não pode ser trocado. Devolve se gravou.
  def name!(page)
    name = ::Crm::BookingV2::ShortName.suggest(page.title, account_id: page.account_id)
    return false if unnamed.where(id: page.id).update_all(short_name: name).zero? # rubocop:disable Rails/SkipsModelValidations

    ::Crm::BookingV2::PersonNames.new(page.reload).assign_missing!
    true
  end
end
