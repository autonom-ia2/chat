# A conta única da IA (#2000): "atendeu", "passou" e "resolveu sozinha" saem daqui, e só daqui. Quem lê:
# CRM › Números › Equipe (a linha da IA, Crm::Numeros::IaNoTime) e a página do agente (Autonomia::AgentesSemanaFinder,
# os cartões da semana, e a lista que cada cartão abre, Agents::AnalyticsController#conversations).
#
#   atendeu         conversas com resposta de robô no período (mensagem de saída de AgentBot: os agentes de IA respondem
#                   pelo robô-espelho do vínculo com a caixa, e o n8n pelo token do robô);
#   passou          conversas que a IA passou para uma pessoa da equipe no período (Crm::Passagem.da_ia_para_equipe, o
#                   critério do "Recebidas da IA"): por horário, a pedido do cliente ou porque não soube;
#   resolveuSozinha conversas resolvidas no período com resposta de robô, sem passagem para pessoa, sem o "humano assumiu"
#                   do core e sem resposta de pessoa, em momento nenhum.
#
# Cada número conta conversas distintas, nunca eventos. Duas leituras, com o mesmo critério:
# - toda a IA da conta (a Equipe): qualquer robô; a passagem conta pelo motivo, mesmo sem `de` gravado;
# - por agente de IA (a página): as respostas dos espelhos do agente (autonomia_agent_inboxes, inclusive os vínculos
#   arquivados) e as passagens gravadas com o próprio agente como origem (o espelho é gravado como o agente,
#   Crm::Passagens). A resolvida sozinha é do agente que respondeu nela.
#
# `conversas`: o universo (relation de Conversation); nil = a conta toda. A Equipe passa as conversas dos funis que quem
# abre enxerga; a página, as conversas que a pessoa pode abrir (ContaDaIa.visiveis), para o cartão e a lista contarem o
# mesmo conjunto.
class Autonomia::ContaDaIa
  DIAS_DA_SEMANA = 7
  # reporting_events e crm_passagens não têm índice no momento do evento (event_end_time, em), só em created_at: o filtro
  # extra por created_at, com folga para o evento gravado um pouco depois, deixa o banco usar o índice (#2000, revisão).
  FOLGA_DO_REGISTRO = 1.day
  NUMEROS = %w[atendeu passou resolveuSozinha].freeze
  ORIGEM_AGENTE = 'Autonomia::Agents::Agent'.freeze
  ESPELHO = <<~SQL.squish.freeze
    INNER JOIN autonomia_agent_inboxes espelho
      ON espelho.agent_bot_id = messages.sender_id AND espelho.account_id = messages.account_id
  SQL

  attr_reader :range

  # A semana da página do agente: os últimos 7 dias, de hoje para trás, desde a meia-noite do primeiro dia no fuso da conta.
  def self.semana(account)
    agora = Crm::Timezone::Resolver.new(account: account).zone_or_default.now
    ((agora - (DIAS_DA_SEMANA - 1).days).beginning_of_day)..agora
  end

  # As conversas que a pessoa pode abrir para ler (a regra da lista de conversas: caixa, funil e função, com quem só lê,
  # #1800); nil = todas.
  def self.visiveis(user:, account:)
    todas = account.conversations
    visiveis = Conversations::PermissionFilterService.new(todas, user, account, for_reading: true).perform
    visiveis.equal?(todas) ? nil : visiveis
  end

  def initialize(account:, range:, conversas: nil)
    @account = account
    @range = range
    @conversas = conversas
  end

  # Toda a IA da conta. As relations devolvem `conversation_id`; conte com `distinct.count(:conversation_id)`.
  def atendidas
    no_universo(respostas_da_ia.where(created_at: @range))
  end

  def passadas
    no_universo(Crm::Passagem.da_ia_para_equipe.where(account_id: @account.id, em: @range, created_at: registro))
  end

  # `universo`: as resolvidas contam só aqui dentro (a Equipe conta só os funis de Atender); nil = o universo da conta.
  def resolvidas_sozinha(universo = nil)
    sem_pessoa = resolvidas_sem_pessoa(universo)
    no_universo(respostas_da_ia.where(conversation_id: sem_pessoa.select(:id)))
  end

  def da_ia
    { atendeu: contar(atendidas), passou: contar(passadas), resolveuSozinha: contar(resolvidas_sozinha) }
  end

  # { agent_id => { atendeu:, passou:, resolveuSozinha: } } em três consultas, qualquer que seja o número de agentes.
  def por_agente(agent_ids)
    return {} if agent_ids.empty?

    atendeu = do_agente(:atendeu, agent_ids).group('espelho.autonomia_agent_id').distinct.count(:conversation_id)
    passou = do_agente(:passou, agent_ids).group(:de_id).distinct.count(:conversation_id)
    sozinha = do_agente(:resolveuSozinha, agent_ids).group('espelho.autonomia_agent_id').distinct.count(:conversation_id)
    agent_ids.index_with do |id|
      { atendeu: atendeu[id].to_i, passou: passou[id].to_i, resolveuSozinha: sozinha[id].to_i }
    end
  end

  # A lista que o cartão abre: a mesma relation do número, presa a um agente.
  def conversas_do_agente(agent_id, numero)
    ids = do_agente(numero, [agent_id]).select(:conversation_id)
    Conversation.where(account_id: @account.id, id: ids)
  end

  # As respostas de robô da conta (sem período): a Equipe também lê para a venda, o nome e o custo. Só as que o cliente vê:
  # a nota interna do espelho (a do encaminhamento, em toda passagem; o aviso ao atendente; a nota da ferramenta) não é
  # resposta (#2000, revisão dos Agentes).
  def respostas_da_ia
    Message.unscope(:order).where(account_id: @account.id, message_type: Message.message_types[:outgoing], sender_type: 'AgentBot',
                                  private: false)
  end

  private

  def registro
    (@range.begin - FOLGA_DO_REGISTRO)..
  end

  def do_agente(numero, agent_ids)
    case numero.to_s
    when 'atendeu' then dos_espelhos(atendidas, agent_ids)
    when 'passou' then passadas.where(de_type: ORIGEM_AGENTE, de_id: agent_ids)
    when 'resolveuSozinha' then dos_espelhos(resolvidas_sozinha, agent_ids)
    else raise ArgumentError, "número da IA desconhecido: #{numero}"
    end
  end

  def dos_espelhos(respostas, agent_ids)
    respostas.joins(ESPELHO).where(espelho: { autonomia_agent_id: agent_ids })
  end

  def contar(relation)
    relation.distinct.count(:conversation_id)
  end

  def no_universo(relation)
    @conversas ? relation.where(conversation_id: @conversas.select(:id)) : relation
  end

  # Resolvidas no período, no universo, sem pessoa no meio em momento nenhum. Só entre as candidatas (as resolvidas do
  # período): nada de varrer o histórico da conta.
  def resolvidas_sem_pessoa(universo)
    resolvidas = ReportingEvent.where(account_id: @account.id, name: 'conversation_resolved', event_end_time: @range,
                                      created_at: registro)
    resolvidas = resolvidas.where(conversation_id: universo.select(:id)) if universo
    candidatas = no_universo(resolvidas).select(:conversation_id)
    Conversation.where(account_id: @account.id, id: candidatas)
                .where.not(id: passadas_para_pessoa(candidatas)).where.not(id: com_resposta_de_pessoa(candidatas))
  end

  # Alguma vez uma pessoa entrou: a passagem gravada ou o "humano assumiu" do core.
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
end
