# A IA no time de CRM › Números, visão "Equipe" (#1992, F5 do #1871). Uma conta só para a IA: todos os agentes de IA e
# robôs da conta viram uma linha, e cada conversa conta uma vez, mesmo que dois deles tenham respondido nela. Conta só
# os clientes que entraram num funil que quem abre enxerga: a conversa do card, pelo card principal ou pelo vínculo
# (crm_card_conversations, Crm::Cards::ConversationLinker); a conversa ligada aos dois jeitos conta uma vez.
#
#   atendeu, passou e resolveuSozinha: a conta única da IA (Autonomia::ContaDaIa, #2000), a mesma da página do agente.
#                   "atendeu" e "passou" somam os funis de Vender e de Atender; "resolveuSozinha" conta só os de Atender.
#                   A frase do topo e a linha da IA leem os mesmos (#1999). As passagens que hoje não ficam gravadas são o
#                   #1887;
#   participou      vendas do mês em conversas que a IA atendeu em algum momento (a IA não leva crédito, Decisão 3);
#   custo           só para o administrador ou o Financeiro (financial_view, #1982): o consumo das respostas dos agentes no mês (Crm::AiUsageEvent
#                   `agente_resposta`), em reais quando a cotação existe. O consumo não guarda o agente: é o de todos.
class Crm::Numeros::IaNoTime
  FEATURE_RESPOSTA = 'agente_resposta'.freeze
  MAX_ROBOS = 50

  # ganhos: { ids: os cards ganhos no mês, moeda: a da tela, valor: false sem sales_value_view (#2075) };
  # custo: true só com financial_view.
  def initialize(account:, range:, cards:, ganhos:, custo:)
    @account = account
    @range = range
    @cards = cards
    @moeda = ganhos[:moeda]
    @ganhos = ganhos[:ids]
    @valor = ganhos.fetch(:valor, true)
    @custo = custo
  end

  # Some só quando a IA não fez nada no mês: nem atendeu, nem passou, nem participou de venda (a resposta pode ser de
  # um mês antes do fechamento), nem resolveu caso sozinha.
  def perform
    numeros = { atendeu: contar(conta.atendidas), passou: contar(conta.passadas),
                venda: @cards.tem?(:venda) ? venda : nil, atende: @cards.tem?(:atende) ? atende : nil }
    return unless fez_algo?(numeros)

    identidade.merge(numeros).merge(custo: @custo ? custo : nil)
  end

  private

  def fez_algo?(numeros)
    [numeros[:atendeu], numeros[:passou], numeros.dig(:venda, :participou).to_i,
     numeros.dig(:atende, :resolveuSozinha).to_i].any?(&:positive?)
  end

  def venda
    vendas = Crm::Relacao.cards_do_funil(@account).where(id: @ganhos, pipeline_id: @cards.ids(:venda)).where(card_com_robo_sql)
    { participou: vendas.count, valor: @valor ? (vendas.where(currency: @moeda).sum(:value_cents) / 100.0).round(2) : nil }
  end

  def atende
    { resolveuSozinha: contar(conta.resolvidas_sozinha(conversas(:atende))) }
  end

  def conta
    @conta ||= Autonomia::ContaDaIa.new(account: @account, range: @range, conversas: conversas_dos_funis)
  end

  def contar(relation)
    relation.distinct.count(:conversation_id)
  end

  # As conversas dos cards dos funis (sem mês: o card pode ter nascido antes), pelo card principal ou pelo vínculo.
  def conversas(tipo)
    conversas_de(@cards.ids(tipo))
  end

  def conversas_dos_funis
    conversas_de(@cards.ids(:venda) + @cards.ids(:atende))
  end

  def conversas_de(pipeline_ids)
    cards = @account.crm_cards.where(pipeline_id: pipeline_ids)
    principais = cards.where.not(conversation_id: nil).select(:conversation_id)
    vinculadas = Crm::CardConversation.where(account_id: @account.id, card_id: cards.select(:id)).select(:conversation_id)
    Conversation.where(account_id: @account.id).where(id: principais)
                .or(Conversation.where(account_id: @account.id, id: vinculadas)).select(:id)
  end

  # O card teve resposta de robô na conversa principal ou numa vinculada.
  def card_com_robo_sql
    vinculadas = Crm::CardConversation.where(Crm::CardConversation.arel_table[:card_id].eq(Crm::Card.arel_table[:id]))
                                      .select(:conversation_id)
    respostas = conta.respostas_da_ia
    resposta = respostas.where('messages.conversation_id = crm_cards.conversation_id').or(respostas.where(conversation_id: vinculadas))
    Arel.sql("EXISTS (#{resposta.select(1).to_sql})")
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
    conta.atendidas.distinct.limit(MAX_ROBOS).pluck(:sender_id)
  end

  def custo
    usd = Crm::AiUsageEvent.for_account(@account.id).where(feature: FEATURE_RESPOSTA, created_at: @range).sum(:cost_estimate).to_d
    taxa = Crm::Ai::ExchangeRate.current[:rate]
    valor, moeda = @moeda == 'BRL' && taxa.present? ? [usd * taxa.to_d, 'BRL'] : [usd, 'USD']
    conversas = conta.respostas_da_ia.where(created_at: @range).distinct.count(:conversation_id)
    { valor: valor.round(2).to_f, porConversa: conversas.zero? ? nil : (valor / conversas).round(2).to_f, moeda: moeda }
  end
end
