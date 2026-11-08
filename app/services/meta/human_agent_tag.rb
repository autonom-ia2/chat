# Tag HUMAN_AGENT no Instagram e no Messenger (#2259).
#
# A política da Meta só deixa usar a tag na resposta de uma PESSOA da equipe, até 7 dias depois da última mensagem do
# cliente. Antes ela saía em toda mensagem com a flag ligada, inclusive de robô, automação e IA.
#
# O critério é a marca da mensagem, não o tipo do remetente: o follow-up de IA do CRM (e outros envios automáticos)
# gravam o remetente como User. Autonomia::Agents::Operate::PessoaDaEquipe.da_pessoa? já separa isso e é vigiado
# pela varredura por AST de envios em nome de pessoa. Usuário de integração (token CRM/MCP) também não é pessoa.
# Dentro das 24 h a resposta vai sem tag (RESPONSE), como qualquer outra.
module Meta::HumanAgentTag
  STANDARD_WINDOW = Conversations::MessageWindowService::MESSAGING_WINDOW_24_HOURS

  module_function

  def apply?(message, config_key)
    return false unless GlobalConfigService.load(config_key, nil)
    return false unless ::Autonomia::Agents::Operate::PessoaDaEquipe.da_pessoa?(message)
    return false if integration_user?(message)

    outside_standard_window?(message.conversation)
  end

  def integration_user?(message)
    AccountUser.exists?(account_id: message.account_id, user_id: message.sender_id, integration: true)
  end

  def outside_standard_window?(conversation)
    last_incoming = conversation.messages.where(account_id: conversation.account_id).incoming.last
    return false if last_incoming.nil?

    Time.current > last_incoming.created_at + STANDARD_WINDOW
  end
end
