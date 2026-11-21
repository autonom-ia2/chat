# #3097: o card ganho é a compra da pessoa. Ganhar, desfazer o ganho, mudar o valor, a moeda ou a pessoa do card ganho
# e apagar o card ganho refazem o resumo de compras da pessoa (Relacionamentos::Compras::Recalcular, `disparar: :venda`),
# depois do commit, num job. É a venda que muda o grupo de compra na hora; o tempo fica com a rotina diária.
#
# Na transação com várias gravações do mesmo card, o after_commit só vê a última em `saved_changes`: cada gravação anota
# as pessoas no after_save, e o after_commit junta e limpa (como Crm::CardAvisaAutomacao).
#
# Limite: só a escrita que passa pelos callbacks do modelo. `update_all`, `delete_all` e a cascata do banco não passam;
# a rotina diária acerta essas pessoas, sem disparar.
module Crm::CardRefazCompras
  extend ActiveSupport::Concern

  MUDAM_A_COMPRA = %w[status contact_id value_cents currency closed_at].freeze
  # O arquivado pode ser um ganho guardado (DESFECHO_ARQUIVADO): conta como talvez ganho, o serviço confere.
  TALVEZ_GANHO = %w[won archived].freeze

  included do
    after_save :anotar_compra
    after_destroy :anotar_compra_apagada
    after_commit :refazer_compras
    after_rollback :esquecer_compras
  end

  private

  def anotar_compra
    return unless saved_changes.keys.intersect?(MUDAM_A_COMPRA)
    return unless TALVEZ_GANHO.include?(status) || TALVEZ_GANHO.include?(status_before_last_save)

    anotar_pessoas(contact_id, contact_id_before_last_save)
  end

  def anotar_compra_apagada
    anotar_pessoas(contact_id) if TALVEZ_GANHO.include?(status)
  end

  def anotar_pessoas(*ids)
    @compras_a_refazer = (@compras_a_refazer || []) | ids.compact
  end

  def refazer_compras
    pessoas = @compras_a_refazer
    @compras_a_refazer = nil
    return if pessoas.blank?

    Relacionamentos::Compras::RecalcularJob.set(queue: :default).perform_later(account_id, pessoas, 'venda')
  end

  def esquecer_compras
    @compras_a_refazer = nil
  end
end
