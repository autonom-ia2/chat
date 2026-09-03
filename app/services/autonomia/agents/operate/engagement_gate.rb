# PORTA ÚNICA "o agente deve atender esta conversa?" (#284 · Entrega 2a), avaliada ANTES de gerar
# a resposta. Duas regras, ambas opcionais e desligadas por padrão (config vazia = comportamento
# de sempre):
#   - público-alvo (config['audience']): árvore de condições sobre o contato/conversa;
#   - horário de atuação (config['response_window']): always | business_hours | outside_business_hours.
# Fonte do horário: Crm::ServiceSchedule da CAIXA (owner Inbox) quando usável; senão o horário
# comercial da própria caixa (working_hours). Sem nenhuma fonte configurada, a caixa conta como
# "sempre aberta" (mesmo contrato do Captain#available_now?).
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

    open = business_open_now
    return true if open.nil? # sem fonte de horário -> sempre coberta

    window == 'business_hours' ? open : !open
  end

  private

  # Sem contato: só 'handoff' explícito bloqueia; vazio/'respond' atende (comportamento histórico).
  def unknown_contact_allowed?
    @agent.config.to_h['audience_unknown_contact'].to_s != 'handoff'
  end

  # true/false quando há fonte de horário; nil quando não há nenhuma.
  def business_open_now
    schedule = service_schedule
    return schedule_open_now?(schedule) if schedule&.usable?

    inbox = @conversation.inbox
    return nil unless inbox&.working_hours_enabled?

    !inbox.out_of_office?
  end

  def service_schedule
    ::Crm::ServiceSchedule.find_by(account_id: @conversation.account_id, owner_type: 'Inbox', owner_id: @conversation.inbox_id)
  end

  def schedule_open_now?(schedule)
    now = Time.current.in_time_zone(schedule.timezone)
    minute = (now.hour * 60) + now.min
    schedule.blocks_for(now.wday).any? { |start_minute, end_minute| minute >= start_minute && minute < end_minute }
  end
end
