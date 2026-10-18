# #1630: a conversa foi passada para um agente de IA (PassarParaIa), por uma pessoa (`:pessoa`), pela Atribuição do CRM
# (`:crm`, inclusive o Sync por assunto) ou por outro agente (`:ia`) — todas as passagens (decisão do Rodrigo, 15/10). O
# agente que recebe lê a conversa inteira, inclusive o que quem passou escreveu, e ELE decide se tem algo útil a dizer
# agora ou se fica calado. Sem regra de palavra nem de "quem falou por último": quem entende linguagem é o modelo.
#
# O turno abre sem mensagem nova do cliente, então não tem a âncora de uma mensagem: a âncora é a passagem (o id em
# Crm::Passagens). A chave `autonomia:passagem:<id>` (SET NX, um dia) garante um turno só por passagem; o turno que
# falha a solta (ResponderAPassagem), para um evento futuro poder tentar. Ele espera a janela do debounce (quem passou
# pode estar escrevendo ainda) e desiste se o cliente escrever depois da passagem: quem responde aí é o turno normal da
# mensagem, que também recebe o contexto da passagem enquanto o agente não falou (`contexto`). Turno normal já em
# andamento quando a passagem chega (ReenfileirarTurno refez o settle): este não abre.
#
# Só com a Fase 2 ligada E a chave própria da conta (LIGADA_KEY, em internal_attributes, como a Fase 2). A Lia (Agente
# de Cotação, `insurance_quote`) fica de fora como destino (decisão do Rodrigo, 18/10): nada aqui vale para ela.
module Autonomia::Agents::Operate::AoReceberPassagem
  LIGADA_KEY = 'autonomia_agents_ao_receber_passagem'.freeze
  TTL = 1.day
  # Até quando o turno normal recebe o contexto da passagem ("logo após a passagem"), se o agente ainda não falou.
  JANELA_DO_CONTEXTO = 1.hour
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

  # Chamado pelo ReenfileirarTurno.ao_trocar_dono quando a troca veio do PassarParaIa e nenhum turno em andamento foi
  # refeito. -> true quando enfileirou o turno da passagem.
  def abrir(conversation)
    destino = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation.reload)
    return false unless destino && aplica_ao_agente?(destino.agent)

    passagem = ::Crm::Passagens.ultima_aberta(conversation)
    return false unless recebida?(passagem, destino.agent)
    return false unless ::Redis::Alfred.set(chave(passagem.id), destino.id, nx: true, ex: TTL.to_i)

    enfileirar(conversation, passagem, destino)
    true
  end

  # O turno da passagem falhou: solta a chave dela (só se ainda for deste vínculo), sem reenfileirar.
  def soltar(passagem, agent_inbox)
    ::Redis::Alfred.delete_if_equals(chave(passagem.id), agent_inbox.id.to_s)
  end

  # A passagem aberta entregou a conversa a este agente.
  def recebida?(passagem, agent)
    passagem.present? && passagem.para_type == agent.class.name && passagem.para_id == agent.id
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

  # A passagem que este agente recebeu há pouco e sobre a qual ainda não falou nada, ou nil. Fora do gate, para a Lia,
  # ou com o agente já tendo falado depois dela: nil (o turno normal fica como antes).
  def pendente(conversation, agent_inbox)
    agent = agent_inbox.agent
    return unless ligada?(conversation.account) && aplica_ao_agente?(agent)

    passagem = ::Crm::Passagens.ultima_aberta(conversation)
    return unless recebida?(passagem, agent) && passagem.em >= JANELA_DO_CONTEXTO.ago
    return if conversation.messages.outgoing.where(sender_type: 'AgentBot', sender_id: agent_inbox.agent_bot_id)
                          .exists?(['created_at > ?', passagem.em])

    passagem
  end

  # O contexto do turno (item `developer`): quem passou e o que não fazer. `silencio`: o sinal de silêncio, só no turno
  # da própria passagem (sem mensagem nova do cliente); no turno normal, o cliente escreveu e espera resposta.
  def contexto(passagem, silencio: nil)
    linhas = [
      "#{quem_passou(passagem.pedida_por)} passou esta conversa para você há pouco. #{como_ler(passagem.pedida_por)}",
      'Não repita o que já foi dito ao cliente e não assuma como suas as promessas ou os prazos de quem atendia ' \
      'antes: fale só do que é seu.',
      'Se você ainda não falou com o cliente nesta conversa, apresente-se em poucas palavras ao falar.'
    ]
    linhas << turno_sem_mensagem_nova(silencio) if silencio
    linhas.join("\n")
  end

  # Quem pediu a passagem: a pessoa (com o nome), o agente de IA (com o nome) ou, sem ninguém, a Atribuição do CRM.
  def quem_passou(ponta)
    return 'A Atribuição do CRM' if ponta.nil?

    nome = ::Crm::Passagens.nome(ponta)
    ponta.pessoa? ? "Uma pessoa da equipe (#{nome})" : "O agente #{nome}"
  end

  def como_ler(ponta)
    return 'Leia a conversa inteira, inclusive o que essa pessoa escreveu ao cliente.' if ponta&.pessoa?

    'Leia a conversa inteira: as respostas anteriores ao cliente podem ter sido de quem atendia antes, não suas.'
  end

  def turno_sem_mensagem_nova(silencio)
    'O cliente não escreveu nada depois da passagem: a última mensagem dele, se houver, já estava na conversa. Decida se ' \
      'há algo útil a dizer agora, como responder o que ficou sem resposta ou continuar de onde quem atendia antes ' \
      "parou. Se não houver nada útil a dizer agora, responda exatamente `#{silencio}` e nada mais."
  end
end
