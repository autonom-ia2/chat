# Quem receberia a conversa numa passagem AGORA (#1601, M16; pedido do Agentes IA): a pessoa que a regra de Atribuição
# do funil/etapa em foco escolheria (pessoa fixa, rodízio por carga ou o nome pedido), entre quem cuida da conversa
# (Crm::Entrega::QuemCuida). SÓ LEITURA: não grava marca, passagem nem convite, e não exige estar online (é previsão).
# Sem ninguém que cuide: nil.
module Crm::Memoria::DonoPrevisto
  module_function

  def para(conversation, card: Crm::Assunto.funil_atual(conversation))
    membros = Crm::Entrega::QuemCuida.new(conversation: conversation, card: card).pessoas
    return if membros.empty?

    seletor(conversation, membros, regra(card)).perform || membros.first
  rescue Crm::Ai::HandoffMemberSelector::PresencaIndisponivel
    membros&.first
  end

  def regra(card)
    return {} if card.nil?

    settings = Crm::Ai::Config.handoff_settings(card.stage, card.pipeline)
    settings[:enabled] ? settings : {}
  end

  def seletor(conversation, membros, regra)
    Crm::Ai::HandoffMemberSelector.new(
      inbox: conversation.inbox, account_id: conversation.account_id, members: membros,
      mode: regra[:selector_mode] || 'round_robin', prefer_online: regra.fetch(:prefer_online, true), require_online: false,
      pool_type: regra[:pool_type] || 'inbox', pool_id: regra[:pool_id], conversation: conversation
    )
  end
end
