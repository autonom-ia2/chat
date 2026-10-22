# Rastro do "excluir de vez" (#2096): quem apagou, quando, o quê e quantos. Só ids e contagens, nunca nome, telefone,
# título ou valor: o que foi apagado não volta por aqui.
#
# Vai para a trilha de Auditoria da conta (tabela `audits`, a mesma do Guia, #536), não para um lugar novo. É a única
# trilha que sobrevive ao apagado: a atividade do card some com ele, e o log do servidor some com a máquina no deploy.
# Gravado na mesma transação que apaga: se a auditoria falhar, nada é apagado.
module Crm::ExclusaoDefinitiva
  ACAO = 'crm_hard_delete'.freeze
  ALVOS = %w[cards funil contato].freeze

  module_function

  # Excluir o contato apagando de vez os cards dele (LGPD): os cards, o contato e o rastro saem juntos ou nada sai.
  def contato!(contact:, user:)
    account = contact.account
    card_ids = account.crm_cards.where(contact_id: contact.id).pluck(:id)
    Crm::Cards::Excluidor.new(account: account, card_ids: card_ids).perform do |ids|
      contact.destroy!
      auditar!(account: account, user: user, alvo: 'contato', card_ids: ids, contact_id: contact.id)
    end
  end

  # alvo: 'cards' (Arquivados), 'funil' (Funis arquivados) ou 'contato' (excluir contato com os cards, LGPD).
  # extras: ids do funil, do contato e contagens, sem texto.
  def auditar!(account:, user:, alvo:, card_ids:, **extras)
    raise ArgumentError, "alvo desconhecido: #{alvo}" unless ALVOS.include?(alvo)

    Audited.audit_class.create!(
      auditable: account, user: user, action: ACAO,
      audited_changes: { 'alvo' => alvo, 'cards_apagados' => card_ids.size, 'card_ids' => card_ids }
                         .merge(extras.compact.transform_keys(&:to_s))
    )
  end
end
