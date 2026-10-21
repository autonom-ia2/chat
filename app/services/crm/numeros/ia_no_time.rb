# A IA no time de CRM › Números, visão "Equipe" (#1992, F5 do #1871). Uma conta só para a IA: todos os agentes de IA e
# robôs da conta viram uma linha, e cada conversa conta uma vez, mesmo que dois deles tenham respondido nela. Conta só
# os clientes que entraram num funil que quem abre enxerga (o card ligado à conversa), separados pelo tipo do funil.
#
#   atendeu         conversas com resposta de robô no mês (mensagem de saída de AgentBot: os agentes de IA respondem
#                   pelo robô-espelho da caixa, e o n8n pelo token do robô), nos funis de Vender e de Atender juntos;
#   passou          conversas que a IA passou para uma pessoa da equipe no mês (Crm::Passagem.da_ia_para_equipe, o
#                   mesmo critério do "Recebidas da IA"), também nos dois tipos de funil. Um número só de cada: a frase
#                   do topo e a linha da IA leem os mesmos (#1999). As passagens que hoje não ficam gravadas são o #1887;
#   participou      vendas do mês em conversas que a IA atendeu em algum momento (a IA não leva crédito, Decisão 3);
#   resolveuSozinha conversas de Atender resolvidas no mês que a IA atendeu, sem passagem para pessoa, sem resposta de
#                   pessoa e sem o "humano assumiu" do core;
#   custo           só para o administrador ou o Financeiro (financial_view, #1982): o consumo das respostas dos agentes no mês (Crm::AiUsageEvent
#                   `agente_resposta`), em reais quando a cotação existe. O consumo não guarda o agente: é o de todos.
class Crm::Numeros::IaNoTime
  FEATURE_RESPOSTA = 'agente_resposta'.freeze
  MAX_ROBOS = 50

  # ganhos: { ids: os cards ganhos no mês, moeda: a da tela }; custo: true só com financial_view.
  def initialize(account:, range:, cards:, ganhos:, custo:)
    @account = account
    @range = range
    @cards = cards
    @moeda = ganhos[:moeda]
    @ganhos = ganhos[:ids]
    @custo = custo
  end

  def perform
    atendeu = atendidas(conversas_dos_funis).count
    passou = passagens(conversas_dos_funis).count
    return if atendeu.zero? && passou.zero?

    identidade.merge(atendeu: atendeu, passou: passou, venda: @cards.tem?(:venda) ? venda : nil,
                     atende: @cards.tem?(:atende) ? atende : nil, custo: @custo ? custo : nil)
  end

  private

  def venda
    vendas = @account.crm_cards.where(id: @ganhos, pipeline_id: @cards.ids(:venda)).where(com_robo_sql('crm_cards.conversation_id'))
    { participou: vendas.count, valor: (vendas.where(currency: @moeda).sum(:value_cents) / 100.0).round(2) }
  end

  def atende
    { resolveuSozinha: resolvidas_sozinha.count }
  end

  # As conversas dos cards dos funis (sem mês: o card pode ter nascido antes).
  def conversas(tipo)
    @account.crm_cards.where(pipeline_id: @cards.ids(tipo)).where.not(conversation_id: nil).select(:conversation_id)
  end

  def conversas_dos_funis
    @account.crm_cards.where(pipeline_id: @cards.ids(:venda) + @cards.ids(:atende)).where.not(conversation_id: nil)
            .select(:conversation_id)
  end

  def respostas_de_robo
    Message.unscope(:order).where(account_id: @account.id, message_type: Message.message_types[:outgoing], sender_type: 'AgentBot')
  end

  def atendidas(conversas)
    respostas_de_robo.where(created_at: @range, conversation_id: conversas).distinct.select(:conversation_id)
  end

  def passagens(conversas)
    Crm::Passagem.da_ia_para_equipe.where(account_id: @account.id, em: @range, conversation_id: conversas)
                 .distinct.select(:conversation_id)
  end

  # Resolvidas no mês, nos funis de Atender, com resposta de robô e sem pessoa no meio em momento nenhum.
  def resolvidas_sozinha
    resolvidas = ReportingEvent.where(account_id: @account.id, name: 'conversation_resolved', event_end_time: @range,
                                      conversation_id: conversas(:atende)).select(:conversation_id)
    Conversation.where(account_id: @account.id, id: resolvidas)
                .where(com_robo_sql('conversations.id'))
                .where.not(id: passadas_para_pessoa(resolvidas)).where.not(id: com_resposta_de_pessoa(resolvidas))
  end

  # Alguma vez uma pessoa entrou: a passagem gravada ou o "humano assumiu" do core.
  # Só entre as candidatas (as resolvidas do mês): nada de varrer o histórico da conta.
  def passadas_para_pessoa(candidatas)
    passagens = Crm::Passagem.da_ia_para_equipe.where(account_id: @account.id, conversation_id: candidatas).select(:conversation_id)
    assumidas = ReportingEvent.where(account_id: @account.id, name: 'conversation_bot_handoff', conversation_id: candidatas)
                              .select(:conversation_id)
    Conversation.where(id: passagens).or(Conversation.where(id: assumidas)).select(:id)
  end

  def com_resposta_de_pessoa(candidatas)
    Message.unscope(:order).where(account_id: @account.id, conversation_id: candidatas, message_type: Message.message_types[:outgoing],
                                  sender_type: 'User', private: false).select(:conversation_id)
  end

  def com_robo_sql(coluna)
    Arel.sql("EXISTS (#{respostas_de_robo.where("messages.conversation_id = #{coluna}").select(1).to_sql})")
  end

  # O nome e o link do agente quando foi um só no mês; com vários, a tela diz "A IA".
  def identidade
    robos = atendidas_ids_de_robo
    agentes = Autonomia::Agents::AgentInbox.where(account_id: @account.id, agent_bot_id: robos).distinct.pluck(:agent_bot_id, :autonomia_agent_id)
    ids_de_agente = agentes.map(&:last).uniq
    return agente_unico(ids_de_agente.first) if ids_de_agente.one? && agentes.map(&:first).uniq.sort == robos.sort
    return { nome: AgentBot.where(id: robos.first).pick(:name), agenteId: nil } if robos.one? && agentes.empty?

    { nome: nil, agenteId: nil }
  end

  def agente_unico(id)
    { nome: Autonomia::Agents::Agent.where(id: id).pick(:name), agenteId: id }
  end

  def atendidas_ids_de_robo
    respostas_de_robo.where(created_at: @range, conversation_id: conversas_dos_funis).distinct.limit(MAX_ROBOS).pluck(:sender_id)
  end

  def custo
    usd = Crm::AiUsageEvent.for_account(@account.id).where(feature: FEATURE_RESPOSTA, created_at: @range).sum(:cost_estimate).to_d
    taxa = Crm::Ai::ExchangeRate.current[:rate]
    valor, moeda = @moeda == 'BRL' && taxa.present? ? [usd * taxa.to_d, 'BRL'] : [usd, 'USD']
    conversas = respostas_de_robo.where(created_at: @range).distinct.count(:conversation_id)
    { valor: valor.round(2).to_f, porConversa: conversas.zero? ? nil : (valor / conversas).round(2).to_f, moeda: moeda }
  end
end
