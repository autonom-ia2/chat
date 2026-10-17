# PORTA ÚNICA "o agente deve atender esta conversa?" (#284 · Entrega 2a), avaliada ANTES de gerar
# a resposta. Duas regras, ambas opcionais e desligadas por padrão (config vazia = comportamento
# de sempre):
#   - público-alvo (config['audience']): árvore de condições sobre o contato/conversa;
#   - horário de atuação (config['response_window']): always | business_hours | outside_business_hours.
# Fonte do horário: Crm::ServiceSchedule da CAIXA (owner Inbox) quando usável; senão o horário
# comercial da própria caixa (working_hours). Com a flag `horario_unico_caixa` (#1619), só o horário
# comercial da caixa, no fuso da conta. Sem nenhuma fonte configurada, a caixa conta como
# "sempre aberta" (mesmo contrato do Captain#available_now?). Quem lê o horário é o
# HorarioDaCaixa, o mesmo leitor do contexto do turno (#1691): o gate e a IA usam a mesma hora.
# Conversa SEM contato (alguns canais abrem a conversa antes de o contato existir): o público-alvo
# não tem o que checar, então o dono escolhe em config['audience_unknown_contact'] —
# 'respond' (padrão: atende) | 'handoff' (bloqueia como 'audience'). Só vale com público preenchido.
class Autonomia::Agents::Operate::EngagementGate
  RESPONSE_WINDOWS = %w[always business_hours outside_business_hours].freeze
  UNKNOWN_CONTACT_POLICIES = %w[respond handoff].freeze

  def initialize(agent:, conversation:)
    @agent = agent
    @conversation = conversation
  end

  # -> nil (pode atender) | 'audience' | 'schedule' (motivo do bloqueio, também o sufixo do evento).
  def blocked_reason
    return 'audience' unless audience_matches?
    return 'schedule' unless available_now?

    nil
  end

  def audience_matches?
    audience = @agent.config.to_h['audience']
    return true if audience.blank?

    contact = @conversation.contact
    return unknown_contact_allowed? if contact.blank?

    ::Autonomia::Agents::AudienceMatcher.new(audience).matches?(contact, @conversation)
  end

  def available_now?
    window = @agent.config.to_h['response_window'].to_s
    return true if window.blank? || window == 'always'

    open = ::Autonomia::Agents::Operate::HorarioDaCaixa.new(conversation: @conversation).aberta_agora
    return true if open.nil? # sem fonte de horário -> sempre coberta

    window == 'business_hours' ? open : !open
  end

  private

  # Sem contato: só 'handoff' explícito bloqueia; vazio/'respond' atende (comportamento histórico).
  def unknown_contact_allowed?
    @agent.config.to_h['audience_unknown_contact'].to_s != 'handoff'
  end
end
