# chat#1648 — Prepend em Api::V1::Accounts::InboxesController#set_agent_bot (a API crua de pôr robô na caixa).
# Caixa com PORTA da plataforma (vínculo AgentInbox de porta, não apagado) não aceita agente de outro sistema por aqui:
# o vínculo da porta ficaria órfão e os dois responderiam. A troca certa é a da aba "Agente de IA" (PUT quem_atende,
# Autonomia::Agents::TrocarQuemAtende), que tira a porta pelo InboxConnector. Recusa com 422 e um `code`:
# - caixa_com_agente_da_plataforma: pediu um robô que não é o espelho da porta desta caixa;
# - desconectar_agente_da_plataforma: pediu para desconectar (agent_bot vazio) a caixa que tem porta nossa, o que
#   soltaria o espelho dela;
# - agente_da_plataforma: pediu o espelho de um agente da plataforma (#1626: espelho não é robô) que não é a porta desta
#   caixa. O agente da plataforma entra pela aba Agente de IA ou pela página dele.
# Caixa só com agente da equipe (área) aceita: a área fica e convive com o agente de outro sistema (decisão do Rodrigo
# de 15/10, opção B; o risco de os dois responderem ficou na #1636). Vale para todas as contas, com ou sem a Fase 2.
#
# TRAVA OS AGENTES DA CAIXA E DEPOIS A CAIXA, a ordem dos caminhos da Autonom.ia (Areas e InboxConnector travam o
# agente e depois a caixa). Quem serializa com um agente entrando agora (que ainda não tem vínculo para ser travado
# aqui) é a trava da CAIXA: o InboxConnector#connect! e o Areas.vincular! conferem a caixa com ela travada, então um
# dos dois espera o outro e enxerga o que ele gravou.
module Autonomia::Agents::CaixaSemAgenteExterno
  def set_agent_bot
    # Só nas contas com a aba "Agente de IA" por caixa (#1648); nas outras, o set_agent_bot do Chatwoot.
    return super unless ::Autonomia::Agents::AgenteIaPorCaixa.ligada?(Current.account)

    codigo = nil
    ActiveRecord::Base.transaction do
      travar_agentes_e_caixa!
      codigo = codigo_da_recusa
      super if codigo.nil?
    end
    recusar(codigo) if codigo
  end

  private

  def travar_agentes_e_caixa!
    agentes = ::Autonomia::Agents::QuemAtendeACaixa.vinculos(@inbox).select(:autonomia_agent_id)
    ::Autonomia::Agents::Agent.where(id: agentes).order(:id).lock.load
    @inbox.lock!
  end

  def codigo_da_recusa
    espelho = ::Autonomia::Agents::QuemAtendeACaixa.espelho_da_porta(@inbox)
    return desconectar(espelho) if @agent_bot.nil?
    return if @agent_bot.id == espelho
    return :caixa_com_agente_da_plataforma if espelho

    :agente_da_plataforma if ::Autonomia::Agents::AgentInbox.espelhos.exists?(agent_bot_id: @agent_bot.id)
  end

  # Desconectar (agent_bot vazio) só solta robô de outro sistema: o espelho da porta sai pela troca ou pelo agente.
  def desconectar(espelho)
    :desconectar_agente_da_plataforma if espelho
  end

  def recusar(codigo)
    Rails.logger.warn("[autonomia][set_agent_bot] recusado code=#{codigo} account=#{Current.account.id} inbox=#{@inbox.id} " \
                      "agent_bot=#{@agent_bot&.id}")
    render json: { error: I18n.t("autonomia.agents.caixa_externo.#{codigo}"), code: codigo.to_s },
           status: :unprocessable_entity
  end
end
