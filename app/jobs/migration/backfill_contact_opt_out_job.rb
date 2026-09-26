# Passa para o contato as recusas gravadas antes do deploy da recusa no contato (chat#713): lead recusado e descadastro de
# e-mail (Contacts::OptOutBackfill). Enfileirado pela migration 20260926180000. Idempotente: pode rodar de novo.
# A falha de uma conta vai para o log e o rastreador de erros e não impede as outras; rodar o job de novo a refaz.
class Migration::BackfillContactOptOutJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    Contacts::OptOutBackfill.accounts_with_legacy_refusals.find_each { |account| backfill(account) }
  end

  private

  def backfill(account)
    counts = Contacts::OptOutBackfill.new(account: account).perform
    Rails.logger.info("[contact_opt_out_backfill] account=#{account.id} opted_out_before=#{counts[:before]} after=#{counts[:after]}")
  rescue StandardError => e
    Rails.logger.error("[contact_opt_out_backfill] account=#{account.id} falhou: #{e.class}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end
