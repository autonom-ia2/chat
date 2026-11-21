# A rotina diária dos grupos de compra (#3097, config/schedule.yml): um Relacionamentos::Compras::RecalcularJob por
# conta que tem venda ou já tem resumo de compras. Refaz a conta inteira: quem passou de grupo com o tempo ("sem comprar
# há 3 a 6 meses", "passou da hora de voltar") dispara o gatilho "entrou no grupo de compra", e o ganho que não passou
# pelo modelo (lote, importação) entra no resumo sem disparar. Também é o preenchimento da primeira vez (a migration
# 20261121150100 o enfileira). Uma conta grande não atrasa as outras: cada uma no seu job.
class Relacionamentos::Compras::VarreduraJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    contas.each { |account_id| Relacionamentos::Compras::RecalcularJob.perform_later(account_id, nil, 'tempo') }
  end

  private

  def contas
    com_venda = Crm::Card.com_desfecho(:won).where.not(contact_id: nil).distinct.pluck(:account_id)
    (com_venda + Relacionamentos::Compra.distinct.pluck(:account_id)).uniq
  end
end
