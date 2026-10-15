# chat#1648 — marcação por caixa: o LEITOR ÚNICO de "quem atende esta caixa", para a aba "Agente de IA" da caixa
# (QuemAtendeController), para a troca (TrocarQuemAtende) e para a recusa do set_agent_bot (CaixaSemAgenteExterno).
# Para quem usa, todos são agentes de IA: os da plataforma (vínculo AgentInbox não apagado, de porta ou de área) e os de
# outro sistema (AgentBotInbox de um AgentBot que não é espelho, AgentInbox.espelhos). `tipo` diz qual é qual só para a
# tela saber onde abrir e o que mandar na troca: 'plataforma' ou 'webhook'.
# Não depende da flag da jornada nem da Fase 2: a regra vale para todas as contas. Os agentes da plataforma só entram nas
# OPÇÕES com o módulo de Agentes ligado na conta (Config.enabled?), como o resto da API deles.
module Autonomia::Agents::QuemAtendeACaixa
  PLATAFORMA = 'plataforma'.freeze
  WEBHOOK = 'webhook'.freeze

  module_function

  # [{ tipo, id, name, papel, avatar_url }]: quem atende primeiro (porta da plataforma ou agente de outro sistema) e
  # depois as áreas por nome.
  def agentes(inbox)
    da_plataforma = vinculos(inbox).includes(:agent).map do |vinculo|
      item(PLATAFORMA, vinculo.agent, vinculo.papel)
    end
    de_outro_sistema = robos_de_outro_sistema(inbox).includes(:agent_bot).map do |bot_inbox|
      item(WEBHOOK, bot_inbox.agent_bot, 'porta')
    end
    (da_plataforma + de_outro_sistema).sort_by { |agente| [agente[:papel] == 'porta' ? 0 : 1, agente[:name].to_s.downcase, agente[:id]] }
  end

  # { tipo, id, name } de quem atende primeiro, ou nil (caixa só de pessoas).
  def primeiro(inbox)
    agentes(inbox).find { |agente| agente[:papel] == 'porta' }&.slice(:tipo, :id, :name)
  end

  # O que a escolha "Quem atende primeiro" oferece: [{ tipo, id, name, recusa }] por nome. `recusa` é o código da troca
  # que o servidor recusaria (a tela mostra o motivo antes de pedir), ou nil.
  # Da plataforma: quem pode atender cliente agora ou ser ligado aqui (o mesmo escopo do agente da equipe,
  # Agent.podem_ser_area: fora interno, rascunho, de sistema, ajudante e parado de propósito), mais quem já atende
  # primeiro. De outro sistema: os AgentBots da conta que não são espelho (#1626).
  def opcoes(inbox)
    atual = primeiro(inbox)
    (opcoes_da_plataforma(inbox, atual) + opcoes_de_outro_sistema(inbox))
      .sort_by { |opcao| [opcao[:name].to_s.downcase, opcao[:tipo], opcao[:id]] }
  end

  def vinculos(inbox)
    ::Autonomia::Agents::AgentInbox.kept.where(inbox_id: inbox.id, account_id: inbox.account_id)
  end

  # AgentBotInbox de agente de outro sistema na caixa (o espelho de agente da plataforma nunca conta). Para ler quem
  # atende, só os ativos (o inativo não recebe conversa: Inbox#active_bot?). `so_ativos: false` é da troca, que tira
  # todos antes de pôr o novo.
  def robos_de_outro_sistema(inbox, so_ativos: true)
    robos = AgentBotInbox.where(inbox_id: inbox.id).where.not(agent_bot_id: ::Autonomia::Agents::AgentInbox.espelhos)
    so_ativos ? robos.active : robos
  end

  # O espelho da porta ativa: o único AgentBot que a caixa com agente da plataforma aceita como robô.
  def espelho_da_porta(inbox)
    vinculos(inbox).porta.pick(:agent_bot_id)
  end

  # Os AgentBots da conta que são agentes de outro sistema: nem espelho, nem robô de sistema (account_id nulo). O robô
  # de sistema fica de fora de propósito: conferido em produção em 15/10, nenhuma caixa usa um (revisão do #1648).
  def agentes_de_outro_sistema(account)
    account.agent_bots.where.not(id: ::Autonomia::Agents::AgentInbox.espelhos)
  end

  def item(tipo, registro, papel)
    { tipo: tipo, id: registro.id, name: registro.name, papel: papel, avatar_url: registro.avatar_url.presence }
  end

  def opcoes_da_plataforma(inbox, atual)
    return [] unless ::Autonomia::Agents::Config.enabled?(inbox.account)

    na_equipe = vinculos(inbox).area.pluck(:autonomia_agent_id).to_set
    atual_id = atual[:id] if atual && atual[:tipo] == PLATAFORMA
    agentes = ::Autonomia::Agents::Agent.podem_ser_area(inbox.account)
                                        .or(::Autonomia::Agents::Agent.where(id: atual_id))
    agentes.pluck(:id, :name).map do |id, name|
      { tipo: PLATAFORMA, id: id, name: name, recusa: na_equipe.include?(id) ? 'agente_ja_e_da_equipe' : nil }
    end
  end

  def opcoes_de_outro_sistema(inbox)
    agentes_de_outro_sistema(inbox.account).pluck(:id, :name).map { |id, name| { tipo: WEBHOOK, id: id, name: name, recusa: nil } }
  end
  private_class_method :item, :opcoes_da_plataforma, :opcoes_de_outro_sistema
end
