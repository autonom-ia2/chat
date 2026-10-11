# Dá endereço curto às páginas de agendamento que nasceram antes dele (#1299): depois do deploy, toda página nova
# (page_version 2) abre em `/a/<conta>/<página>` sem ninguém precisar abrir em Editar. Roda pela migration
# `BackfillBookingShortNames`.
#
# Por conta que tem página nova, numa transação só dela:
# - cria o endereço da conta, se ainda não existe (`AccountAddress.ensure!`, a partir do nome da conta);
# - para cada página SEM nome, grava um nome a partir do título, único na conta (`ShortName.suggest`);
# - dá apelido às pessoas dessas páginas que ainda não têm (`PersonNames`).
#
# Página que já tem nome não é tocada, então rodar de novo não muda nada. Só a coluna `short_name` é gravada
# (`update_column`): uma página antiga que hoje não passaria em outra validação não pode ficar sem endereço, e
# o `updated_at` da página fica como estava (o do link que ganha apelido muda). Conta que falha é desfeita sozinha,
# registrada no log e não para as outras.
class Crm::BookingV2::ShortNameBackfill
  Result = Struct.new(:accounts, :pages, :failed_account_ids)

  def self.run
    new.run
  end

  def run
    result = Result.new(0, 0, [])
    ::Account.where(id: unnamed_pages.select(:account_id)).find_each do |account|
      result.pages += backfill(account)
      result.accounts += 1
    rescue StandardError => e
      Rails.logger.error("[booking_short_name_backfill] conta #{account.id}: #{e.class}: #{e.message}")
      result.failed_account_ids << account.id
    end
    result
  end

  private

  def unnamed_pages
    ::Crm::AgentBookingProfile.new_pages.where(short_name: [nil, ''])
  end

  def backfill(account)
    ::Crm::AgentBookingProfile.transaction do
      ::Crm::BookingV2::AccountAddress.ensure!(account)
      pages = unnamed_pages.where(account_id: account.id).order(:id).to_a
      pages.each { |page| name!(page) }
      pages.size
    end
  end

  def name!(page)
    name = ::Crm::BookingV2::ShortName.suggest(page.title, account_id: page.account_id)
    page.update_column(:short_name, name) # rubocop:disable Rails/SkipsModelValidations
    ::Crm::BookingV2::PersonNames.new(page).assign_missing!
  end
end
