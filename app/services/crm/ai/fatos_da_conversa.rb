# IA entende a conversa, F1 — fatos da conversa (flag de conta `crm_ia_fatos_da_conversa`). Três correções, todas de
# FATO (quem falou, em que ordem, a que horas); quem interpreta o texto é sempre o modelo:
#
# 1. Quem falou e em que ordem chega igual às duas IAs. A de assunto (Autonomia::Decisores::Estado com `papeis: true`)
#    passa a ler o papel de cada mensagem (Crm::Ai::PapelDaMensagem) e a hora; a de etapa (Crm::Ai::ContextBuilder) lê
#    `after` (o papel de quem falou logo antes de cada mensagem do cliente) e `customer_waiting_since` (desde quando o
#    cliente espera resposta). Mensagens seguidas do cliente antes de o atendimento falar não respondem à equipe.
# 2. A fala pública do nosso agente de IA relê o card em foco (Crm::Conversations::CardEmFoco), com a espera da equipe
#    e no máximo MAX_AVALIACOES_DO_ROBO_POR_DIA por card. Não contam: follow-up e Agendamento (envio automático), robô
#    de fora, nota privada, envio que falhou e o agente protegido (o de cotação, `instrucao_mantida?`).
# 3. A passagem para pessoa que o nosso assistente prometeu ao cliente e ninguém cumpriu é honrada pela IA do CRM
#    (Crm::Ai::HandoffExecutor), mesmo com o agente dono da conversa, exceção à regra do #1673. Problema resolvido
#    depois da promessa não passa. Nunca com o agente protegido.
#
# Sem a flag: prompt, schema, entrada e comportamento iguais aos de antes.
module Crm::Ai::FatosDaConversa
  FLAG = 'crm_ia_fatos_da_conversa'.freeze
  # A avaliação agendada pela fala do nosso robô: fica na sugestão e no log, para medir à parte.
  TRIGGER_DO_ROBO = 'fala_do_robo'.freeze
  MAX_AVALIACOES_DO_ROBO_POR_DIA = 6
  CONTADOR = 'robo_avaliacoes'.freeze

  # Os rótulos que a IA de assunto lê (o prompt dela é em inglês).
  ROTULOS = {
    'customer' => 'Customer',
    'human_agent' => 'Team member',
    'platform_agent' => 'Our assistant (AI)',
    'external_agent' => 'Automatic message (other system)'
  }.freeze

  # Vai à pergunta do Jev e ao modelo maior da IA de assunto (Crm::Subjects::Question / Reviewer).
  INSTRUCAO_DO_ASSUNTO = 'Each message line starts with the local time and who wrote it: the customer, a team member, our ' \
                         'assistant (AI) or an automatic message from another system. Several customer messages in a row, ' \
                         'before anyone answers, are one single turn of the customer: read them together, and they do ' \
                         'not answer anything the team or our assistant said later. Messages from our assistant or from ' \
                         'another system are never a request from the customer.'.freeze

  # Vai no FIM do prefixo da IA de etapa (Crm::Ai::ClassifierPrompt.para), só com a flag: o prefixo das contas sem ela
  # não muda.
  ORDEM = <<~ORDEM.strip
    ORDEM DA CONVERSA E PROMESSA DO NOSSO ASSISTENTE:
    - Em "recent_messages", cada mensagem do cliente traz "after": o "role" de quem falou logo antes dela (null quando
      é a primeira da lista). Mensagens do cliente com "after": "customer" fazem parte de uma sequência que o cliente
      mandou antes de qualquer resposta do atendimento: leia a sequência como uma fala só. Ela não responde a nada que
      a equipe ou o nosso assistente disse depois e, sozinha, não é sinal de avanço de etapa.
    - "conversation_state.customer_waiting_since" preenchido: o cliente escreveu e ninguém do atendimento respondeu
      desde essa hora. null: a última fala é do atendimento.
    - Mensagem de "platform_agent" é do nosso assistente de IA (ou um envio automático nosso); de "external_agent", de
      outro sistema. Nenhuma das duas é pedido do cliente nem prova do que o cliente quer ou aceitou.
    - "handoff.promised_by_our_assistant": true SOMENTE quando o nosso assistente ("platform_agent") disse ao cliente
      que uma pessoa da equipe vai assumir ou atender, "conversation_state.assigned_to_human" é false e as mensagens
      depois dessa promessa não mostram o problema resolvido. Se depois da promessa a conversa mostra o problema
      resolvido, false. Promessa de outro sistema ("external_agent") ou de uma pessoa da equipe não conta. Sem
      promessa, false. É um fato à parte: "intent" e "should_handoff" seguem as regras de sempre, e o sistema decide o
      que fazer com a promessa.
  ORDEM

  PROMESSA = {
    type: 'boolean',
    description: 'true SOMENTE quando o nosso assistente (platform_agent) prometeu ao cliente que uma pessoa vai assumir, ' \
                 'ninguém assumiu e o problema não foi resolvido depois da promessa (ORDEM DA CONVERSA). Senão, false.'
  }.freeze

  module_function

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # O schema de um card com `promised_by_our_assistant` no objeto `handoff` (obrigatório, como todo campo do schema).
  def com_promessa(schema)
    corpo = schema[:schema]
    handoff = corpo[:properties][:handoff]
    novo = handoff.merge(properties: handoff[:properties].merge(promised_by_our_assistant: PROMESSA),
                         required: [*handoff[:required], 'promised_by_our_assistant'])
    schema.merge(schema: corpo.merge(properties: corpo[:properties].merge(handoff: novo))).freeze
  end

  # A promessa que a avaliação leu (saída do modelo, não texto do cliente).
  def promessa?(handoff)
    return false if handoff.blank?

    dados = handoff.respond_to?(:with_indifferent_access) ? handoff.with_indifferent_access : handoff.to_h
    ActiveModel::Type::Boolean.new.cast(dados[:promised_by_our_assistant]) == true
  end

  # Cada mensagem do cliente com o papel de quem falou logo antes NA MESMA CONVERSA (`after`; o card pode juntar várias
  # conversas, e a fala de outra conversa não vem "antes" desta); as outras, iguais. Novos hashes.
  def com_ordem(mensagens)
    anterior = {}
    mensagens.map do |mensagem|
      chave = mensagem[:conversation_id]
      antes = anterior[chave]
      anterior[chave] = mensagem[:role]
      mensagem[:role] == 'customer' ? mensagem.merge(after: antes) : mensagem
    end
  end

  # trios: [conversa, papel, hora] em ordem de chegada. Em cada conversa, a hora da 1ª mensagem do cliente depois da
  # última fala de qualquer outro papel; entre as conversas em que o cliente espera, a mais antiga. nil quando em todas
  # a última fala não é do cliente.
  def cliente_espera_desde(trios)
    trios.group_by(&:first).values.filter_map { |da_conversa| espera_na_conversa(da_conversa) }.min&.iso8601
  end

  def espera_na_conversa(trios)
    trios.reverse.take_while { |(_conversa, papel, _hora)| papel == 'customer' }.last&.last
  end

  # A fala pública do NOSSO agente de IA ao cliente (não follow-up nem Agendamento, que saem em nome de uma pessoa; não
  # robô de fora; não o agente protegido).
  def fala_do_nosso_robo?(message)
    return false unless message.outgoing? && !message.private? && !message.failed? && message.sender_type == 'AgentBot'

    robos = Crm::Ai::PapelDaMensagem.robos_da_conta(message.account_id)
    Crm::Ai::PapelDaMensagem.de(message, robos: robos) == 'platform_agent' && !agente_protegido?(message.account_id, message.sender_id)
  end

  # O agente cuja instrução é mantida pela Autonom.ia (o de cotação) fica fora das duas pontas da F1.
  def agente_protegido?(account_id, agent_bot_id)
    Autonomia::Agents::AgentInbox.where(account_id: account_id, agent_bot_id: agent_bot_id).includes(:agent)
                                 .any? { |vinculo| vinculo.agent&.instrucao_mantida? }
  end

  # O agente protegido está no nome de uma conversa do card ainda não resolvida (está atendendo). A IA do CRM não fecha o
  # card, não sugere fechar nem sugere "era teste" por cima dele (F3, Crm::Ai::FecharCard e Crm::Ai::NaoENegocio).
  def agente_protegido_atendendo?(card)
    conversas = [card.conversation_id, *card.card_conversations.pluck(:conversation_id)].compact.uniq
    robos = Conversation.where(account_id: card.account_id, id: conversas, ai_assignee_type: 'AgentBot')
                        .where.not(status: :resolved).distinct.pluck(:assignee_agent_bot_id)
    robos.any? { |robo| agente_protegido?(card.account_id, robo) }
  end

  # O teto de avaliações pela fala do robô, no `ai` do metadata do card (lido sob a trava do Crm::Ai::Observer).
  def cota_do_robo_esgotada?(estado)
    contador = estado[CONTADOR].to_h
    contador['dia'] == Date.current.iso8601 && contador['total'].to_i >= MAX_AVALIACOES_DO_ROBO_POR_DIA
  end

  def contar_avaliacao_do_robo(estado)
    contador = estado[CONTADOR].to_h
    hoje = Date.current.iso8601
    { CONTADOR => { 'dia' => hoje, 'total' => (contador['dia'] == hoje ? contador['total'].to_i : 0) + 1 } }
  end
end
