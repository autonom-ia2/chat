# Rastro do "excluir de vez" (#2096): quem apagou, quando, o quê e quantos. Só ids, contagens e códigos, nunca nome,
# telefone, título ou valor: o que foi apagado não volta por aqui.
#
# Vai para a trilha de Auditoria da conta (tabela `audits`, a mesma do Guia, #536), não para um lugar novo. É a única
# trilha que sobrevive ao apagado: a atividade do card some com ele, e o log do servidor some com a máquina no deploy.
# Gravado na mesma transação que apaga: se a auditoria falhar, nada é apagado.
#
# O funil com cards é excluído num job (Crm::Pipelines::ExcluirDeVezJob), depois de a API já ter respondido 202. Quando
# o job desiste, o desfecho também fica aqui (FALHOU), com o motivo em código, para a tela mostrar o que aconteceu.
module Crm::ExclusaoDefinitiva
  ACAO = 'crm_hard_delete'.freeze
  FALHOU = 'crm_hard_delete_failed'.freeze
  ALVOS = %w[cards funil contato].freeze

  # O que era para sair mudou entre a conferência e as travas, e nada foi apagado. `motivo`:
  # - not_archived: um card ou o funil foi restaurado (não está mais arquivado);
  # - cards_changed: um card sumiu ou entrou no funil nesse meio tempo;
  # - pipeline_has_cards: o funil vazio ganhou card antes de ser apagado;
  # - target_unavailable: o funil de destino dos cards foi arquivado ou apagado;
  # - already_deleted: outro pedido igual já apagou o funil (dois cliques).
  # `canceladas`: reuniões futuras que já tinham sido canceladas no calendário antes da desistência. Ficam canceladas
  # (o cliente já foi avisado), com a atividade "reunião cancelada" no card.
  class Mudou < StandardError
    attr_reader :motivo, :canceladas

    def initialize(motivo, canceladas: [])
      @motivo = motivo
      @canceladas = canceladas
      super("permanent delete aborted: #{motivo}")
    end
  end

  module_function

  # Excluir o contato apagando de vez os cards dele (LGPD): os cards (abertos, ganhos ou arquivados), o contato e o
  # rastro saem juntos ou nada sai.
  def contato!(contact:, user:)
    account = contact.account
    card_ids = account.crm_cards.where(contact_id: contact.id).pluck(:id)
    Crm::Cards::Excluidor.new(account: account, card_ids: card_ids, somente_arquivados: false).perform do |ids|
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

  # O job do funil desistiu: nada foi apagado. motivo: um código de Mudou, meeting_cancel_failed ou card_rejected.
  # extras: só ids e nomes de campo, sem texto do card.
  def falhou!(account:, user:, alvo:, motivo:, **extras)
    raise ArgumentError, "alvo desconhecido: #{alvo}" unless ALVOS.include?(alvo)

    Audited.audit_class.create!(
      auditable: account, user: user, action: FALHOU,
      audited_changes: { 'alvo' => alvo, 'motivo' => motivo }.merge(extras.compact.transform_keys(&:to_s))
    )
  end
end
