# chat#1648 — Prepend em Api::V1::Accounts::InboxesController#set_agent_bot (aba "Agente externo" da caixa).
# Caixa atendida por agente da plataforma (vínculo AgentInbox não apagado, de porta ou de área) não aceita agente
# externo (n8n, Zapier...): o vínculo ficaria órfão e os dois responderiam. Recusa com 422 e um `code`:
# - caixa_com_agente_da_plataforma: pediu um robô que não é o espelho da porta desta caixa;
# - desconectar_agente_da_plataforma: pediu para desconectar (agent_bot vazio) a caixa que tem porta nossa, o que
#   soltaria o espelho dela. Quem tira o agente da caixa é a página do agente (InboxConnector, Areas).
# Vale para todas as contas, com ou sem a Fase 2.
#
# TRAVA OS AGENTES DA CAIXA E DEPOIS A CAIXA, a ordem dos caminhos da Autonom.ia (OndeTrabalhar, Areas, InboxConnector):
# um agente entrando na caixa ao mesmo tempo espera esta gravação, ou esta conferência já o enxerga.
module Autonomia::Agents::CaixaSemAgenteExterno
  def set_agent_bot
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
    return unless ::Autonomia::Agents::QuemAtendeACaixa.vinculos(@inbox).exists?

    espelho = ::Autonomia::Agents::QuemAtendeACaixa.espelho_da_porta(@inbox)
    if @agent_bot
      :caixa_com_agente_da_plataforma unless @agent_bot.id == espelho
    elsif espelho
      :desconectar_agente_da_plataforma
    end
  end

  def recusar(codigo)
    Rails.logger.warn("[autonomia][set_agent_bot] recusado code=#{codigo} account=#{Current.account.id} inbox=#{@inbox.id} " \
                      "agent_bot=#{@agent_bot&.id}")
    render json: { error: I18n.t("autonomia.agents.caixa_externo.#{codigo}"), code: codigo.to_s },
           status: :unprocessable_entity
  end
end
