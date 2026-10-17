# O horário de atendimento da caixa, lido por UMA regra só (#1691): a do EngagementGate (#284), que decide se o agente
# em "Só no horário"/"Só fora do horário" atende agora, e a do contexto do turno (EsperaForaDoHorario), que diz à IA
# quando a equipe volta. Assim a IA nunca anuncia uma hora diferente da que o gate usa.
#
# Fonte, na ordem:
#   1. Crm::ServiceSchedule da caixa (dono Inbox), quando usável e a flag `horario_unico_caixa` (#1619) está DESLIGADA.
#      Fuso: o do próprio calendário.
#   2. O horário de atendimento do Chatwoot (`working_hours` + `working_hours_enabled`), pelo Inbox#out_of_office?. Fuso:
#      `inbox.timezone`. Com a flag ligada é o fuso da conta (FusoDaConta); SEM a flag é o fuso gravado na caixa, que
#      nasce com o da conta (OutOfOffisable#apply_default_timezone) mas pode ter sido trocado na tela da caixa.
#   3. Nenhuma: `aberta_agora` devolve nil (a caixa conta como "sempre aberta", mesmo contrato do Captain#available_now?).
#
# O instante é o Time.current da construção; o Inbox#out_of_office? do Chatwoot lê o próprio relógio (o mesmo instante,
# a menos de microssegundos).
class Autonomia::Agents::Operate::HorarioDaCaixa
  DIAS_PROCURADOS = 7

  def initialize(conversation:)
    @conversation = conversation
    @inbox = conversation.inbox
    @agora = Time.current
  end

  # true/false quando há fonte de horário; nil quando não há nenhuma.
  def aberta_agora
    return calendario_aberto_agora? if calendario
    return nil unless @inbox&.working_hours_enabled?

    !@inbox.out_of_office?
  end

  # A próxima abertura depois de agora, no fuso da fonte, ou nil sem nenhum dia aberto (ou sem fonte).
  # Horário de verão: se a abertura cair numa hora que não existe no fuso (relógio adiantado à meia-noite, por exemplo),
  # o ActiveSupport::TimeZone#local a empurra para a primeira hora que existe (00:00 vira 01:00), que é quando a caixa
  # de fato abre naquele dia.
  def proxima_abertura
    return unless calendario || @inbox&.working_hours_enabled?

    (0..DIAS_PROCURADOS).each do |dias|
      dia = local.to_date + dias
      abre = inicios_do_dia(dia).find { |inicio| inicio > @agora }
      return abre if abre
    end
    nil
  end

  def fuso
    calendario ? calendario.timezone : @inbox.timezone
  end

  def local
    @local ||= @agora.in_time_zone(fuso)
  end

  private

  # Com a flag `horario_unico_caixa`, o calendário de caixa do CRM não é lido (#1619).
  def calendario
    return @calendario if defined?(@calendario)

    @calendario = if ::Autonomia::HorarioUnicoCaixa.ligado?(@conversation.account)
                    nil
                  else
                    ::Crm::ServiceSchedule.find_by(account_id: @conversation.account_id, owner_type: 'Inbox',
                                                   owner_id: @conversation.inbox_id)&.then { |agenda| agenda if agenda.usable? }
                  end
  end

  def calendario_aberto_agora?
    minuto = (local.hour * 60) + local.min
    calendario.blocks_for(local.wday).any? { |inicio, fim| minuto >= inicio && minuto < fim }
  end

  # Os instantes em que a caixa abre no `dia` (data local da fonte).
  def inicios_do_dia(dia)
    minutos = calendario ? calendario.blocks_for(dia.wday).map(&:first) : abertura_do_chatwoot(dia.wday)
    zona = ActiveSupport::TimeZone[fuso]
    minutos.map { |minuto| zona.local(dia.year, dia.month, dia.day, minuto / 60, minuto % 60) }
  end

  # O minuto do dia em que a caixa abre pelo horário do Chatwoot (dia aberto o dia todo = 0), ou [] em dia fechado.
  def abertura_do_chatwoot(wday)
    horario = @inbox.working_hours.find { |item| item.day_of_week == wday }
    return [] if horario.nil? || horario.closed_all_day?

    [(horario.open_hour * 60) + horario.open_minutes]
  end
end
