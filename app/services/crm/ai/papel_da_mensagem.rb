# Quem falou numa mensagem da conversa, num lugar só (IA entende a conversa, F1). Antes a regra morava no
# Crm::Ai::ContextBuilder e a IA de assunto lia só "cliente" e "equipe": o nosso assistente, a pessoa, o eco do celular e
# a automação de fora eram todos "equipe" para ela. Agora as duas IAs leem o mesmo papel, daqui.
#
# Quatro papéis, não dois. "Cliente cobrou e só o bot respondeu" é urgente; "humano respondeu há 5 minutos" não é.
# - customer: mensagem recebida.
# - platform_agent: o nosso agente de IA (AgentBot de um vínculo Autonom.ia) e os envios automáticos da plataforma em
#   nome de uma pessoa (follow-up do CRM, convite e aviso do Agendamento). O follow-up sai em nome do responsável
#   (MessageSender usa created_by/assignee): sem esta regra, a própria IA reaparecia como pessoa do time e o cérebro
#   concluía que houve pergunta humana sem resposta (a IA cobrou o mesmo cliente duas vezes pelo mesmo questionário).
# - human_agent: uma pessoa da equipe, inclusive o eco do que ela mandou pelo app do celular (`external_echo`, sem
#   remetente). Efeito conhecido (o mesmo do PessoaDaEquipe): o eco da PRÓPRIA bolha da IA que o reconciliador do
#   Híbrido não casou a tempo vira mensagem nova e aparece aqui como pessoa.
# - external_agent: outro AgentBot (integração) ou saída sem remetente (automação, API). Não vira um quinto papel: o
#   modelo conhece só quatro, e um valor fora deles o fazia adivinhar.
#
# Só estrutura (direção, remetente, marcas gravadas pela plataforma); nada do texto.
module Crm::Ai::PapelDaMensagem
  # As marcas que o Agendamento grava no convite e no aviso (Crm::BookingV2::InviteDeliverer / Notices).
  MARCAS_DO_AGENDAMENTO = %w[crm_booking_invite_id crm_booking_notice].freeze

  module_function

  # robos: os ids dos AgentBots da plataforma na conta (.robos_da_conta), ou quem os lê (`call`), para a consulta só
  # acontecer quando a mensagem é de um AgentBot (como antes da F1, no Crm::Ai::ContextBuilder).
  def de(message, robos:)
    return 'customer' if message.incoming?
    return 'platform_agent' if envio_da_plataforma?(message)
    return 'human_agent' if eco_do_celular?(message)

    case message.sender_type
    when 'User' then 'human_agent'
    when 'AgentBot' then robo_da_plataforma?(message, robos) ? 'platform_agent' : 'external_agent'
    else 'external_agent'
    end
  end

  # Bot da plataforma = AgentBot criado por um agente Autonom.ia (Operate::Responder posta com
  # sender_id = agent_inbox.agent_bot_id). Qualquer outro AgentBot é integração externa.
  def robo_da_plataforma?(message, robos)
    (robos.respond_to?(:call) ? robos.call : robos).include?(message.sender_id)
  end

  def robos_da_conta(account_id)
    Autonomia::Agents::AgentInbox.where(account_id: account_id).pluck(:agent_bot_id).compact.to_set
  end

  def envio_da_plataforma?(message)
    atributos = message.content_attributes.to_h
    atributos['crm_follow_up_id'].present? || MARCAS_DO_AGENDAMENTO.any? { |marca| atributos[marca].present? }
  end

  def eco_do_celular?(message)
    message.sender_type.blank? && message.content_attributes.to_h['external_echo'].present?
  end
end
