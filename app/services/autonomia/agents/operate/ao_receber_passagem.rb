# #1630: uma PESSOA passou a conversa para um agente de IA (PassarParaIa, `por: :pessoa`). O agente que recebe lê a
# conversa inteira, inclusive o que a pessoa escreveu, e ELE decide se tem algo útil a dizer agora ou se fica calado. Sem
# regra de palavra nem de "quem falou por último": quem entende linguagem é o modelo (decisão do Rodrigo, 15/10).
#
# O turno abre sem mensagem nova do cliente, então não tem a âncora de uma mensagem: a âncora é a passagem (o id em
# Crm::Passagens). A chave `autonomia:passagem:<id>` (SET NX, um dia) garante um turno só por passagem. Ele espera a
# janela do debounce (a pessoa pode estar escrevendo ainda) e desiste se o cliente escrever depois da passagem: quem
# responde aí é o turno normal da mensagem, que também recebe o contexto da passagem enquanto o agente não falou
# (`contexto`). Turno normal já em andamento quando a passagem chega (ReenfileirarTurno refez o settle): este não abre.
#
# Só com a Fase 2 ligada E a chave própria da conta (LIGADA_KEY, em internal_attributes, como a Fase 2). A Lia (Agente
# de Cotação, `insurance_quote`) fica de fora (decisão do Rodrigo, 18/10): nada aqui vale para ela.
module Autonomia::Agents::Operate::AoReceberPassagem
  LIGADA_KEY = 'autonomia_agents_ao_receber_passagem'.freeze
  TTL = 1.day
  FASE = 'passagem'.freeze

  module_function

  def ligada?(account)
    return false if account.blank?
    return false unless ::Autonomia::Agents::Config.enabled?(account) && ::Autonomia::Agents::Fase2.ligada?(account)

    ::Autonomia::Agents::Fase2::BOOLEAN.cast(account.internal_attributes.to_h[LIGADA_KEY]) || false
  end

  def aplica_ao_agente?(agent)
    agent.present? && agent.agent_type != 'insurance_quote'
  end

  def chave(passagem_id)
    "autonomia:passagem:#{passagem_id}"
  end

  # Chamado pelo ReenfileirarTurno.ao_trocar_dono quando a troca veio de uma pessoa e nenhum turno em andamento foi
  # refeito. -> true quando enfileirou o turno da passagem.
  def abrir(conversation)
    destino = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation.reload)
    return false unless destino && aplica_ao_agente?(destino.agent)

    passagem = ::Crm::Passagens.ultima_aberta(conversation)
    return false unless recebida_de_pessoa?(passagem, destino.agent)
    return false unless ::Redis::Alfred.set(chave(passagem.id), destino.id, nx: true, ex: TTL.to_i)

    enfileirar(conversation, passagem, destino)
    true
  end

  # A passagem aberta foi pedida por uma pessoa e entregou a conversa a este agente.
  def recebida_de_pessoa?(passagem, agent)
    passagem.present? && passagem.pedida_por_type == 'User' &&
      passagem.para_type == agent.class.name && passagem.para_id == agent.id
  end

  def enfileirar(conversation, passagem, destino)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:turno_da_passagem, conversation_id: conversation.id,
                                                                                  passagem: passagem.id, agent_inbox: destino.id)
    espera = ::Autonomia::Agents::Config.debounce_seconds_for(destino.agent)
    ids = [conversation.id, passagem.id, destino.id]
    ActiveRecord.after_all_transactions_commit do
      ::Autonomia::Agents::Operate::ReplyJob.set(wait: espera).perform_later(ids[0], ids[1], FASE, ids[2])
    end
  end

  # A passagem que este agente recebeu de uma pessoa e sobre a qual ainda não falou nada, ou nil. Fora do gate, para a
  # Lia, ou com o agente já tendo falado depois dela: nil (o turno normal fica como antes).
  def pendente(conversation, agent_inbox)
    agent = agent_inbox.agent
    return unless ligada?(conversation.account) && aplica_ao_agente?(agent)

    passagem = ::Crm::Passagens.ultima_aberta(conversation)
    return unless recebida_de_pessoa?(passagem, agent)
    return if conversation.messages.outgoing.where(sender_type: 'AgentBot', sender_id: agent_inbox.agent_bot_id)
                          .exists?(['created_at > ?', passagem.em])

    passagem
  end

  # O contexto do turno (item `developer`): quem passou e o que não fazer. `silencio`: o sinal de silêncio, só no turno
  # da própria passagem (sem mensagem nova do cliente); no turno normal, o cliente escreveu e espera resposta.
  def contexto(passagem, silencio: nil)
    nome = ::Crm::Passagens.nome(passagem.pedida_por)
    linhas = [
      "Uma pessoa da equipe (#{nome}) passou esta conversa para você há pouco. Leia a conversa inteira, inclusive o " \
      'que essa pessoa escreveu ao cliente.',
      'Não repita o que ela já disse e não assuma como suas as promessas ou os prazos que ela deu: fale só do que é seu.',
      'Se você ainda não falou com o cliente nesta conversa, apresente-se em poucas palavras ao falar.'
    ]
    linhas << turno_sem_mensagem_nova(silencio) if silencio
    linhas.join("\n")
  end

  def turno_sem_mensagem_nova(silencio)
    'O cliente não escreveu nada depois da passagem: a última mensagem dele, abaixo, já estava na conversa. Decida se ' \
      'há algo útil a dizer agora, como responder o que ficou sem resposta ou continuar de onde a pessoa parou. Se não ' \
      "houver nada útil a dizer agora, responda exatamente `#{silencio}` e nada mais."
  end
end
