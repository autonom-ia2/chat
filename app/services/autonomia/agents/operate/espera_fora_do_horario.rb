# A conversa espera uma pessoa e a equipe está fora do horário da caixa (#1691, decisão do Rodrigo de 16/10/2026). A IA
# segue atendendo (o modo do agente não muda) e passa a SABER disso: que a conversa espera alguém da equipe e quando a
# equipe volta, pela próxima abertura do horário de atendimento da caixa. Como dizer ao cliente fica com ela.
#
# "Espera uma pessoa" é o mesmo critério de Message#waiting_for_person?: a marca da passagem do robô (#1377) ou a do
# motor de entrega (#1454), sem pessoa no nome. "Fora do horário" é o mesmo do Chatwoot (Inbox#out_of_office?), no fuso
# que ele usa (`inbox.timezone`, que com a flag `horario_unico_caixa` é o da conta). Só com a Fase 2 (quem chama checa).
class Autonomia::Agents::Operate::EsperaForaDoHorario
  DIAS_DA_SEMANA = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  DIAS_PROCURADOS = 7
  SEM_DATA_DE_VOLTA = 'Esta caixa não tem dia de atendimento marcado: não há data de volta da equipe, e você não deve ' \
                      'inventar uma.'.freeze

  def initialize(conversation:, agora: Time.current)
    @conversation = conversation
    @inbox = conversation.inbox
    @agora = agora.in_time_zone(@inbox.timezone)
  end

  # O texto do contexto do turno, ou nil quando a conversa não espera pessoa ou a caixa está no horário.
  def texto
    return unless esperando_pessoa? && fora_do_horario?

    abertura = proxima_abertura
    volta = abertura ? "A equipe volta #{quando(abertura)}." : SEM_DATA_DE_VOLTA
    'SITUAÇÃO DESTA CONVERSA NESTE TURNO: o cliente está esperando alguém da equipe, e a equipe está fora do horário ' \
      "de atendimento agora (#{quando(@agora, atual: true)}). #{volta} Você decide se e como contar isso ao cliente. " \
      'Continue ajudando no que souber, e não prometa que alguém da equipe responde antes disso.'
  end

  def proxima_abertura
    zona = ActiveSupport::TimeZone[@inbox.timezone]
    (0..DIAS_PROCURADOS).each do |dias|
      dia = @agora.to_date + dias
      horario = horarios[dia.wday]
      next if horario.nil? || horario.closed_all_day?

      abre = zona.local(dia.year, dia.month, dia.day, horario.open_hour, horario.open_minutes)
      return abre if abre > @agora
    end
    nil
  end

  private

  def esperando_pessoa?
    @conversation.assignee_id.blank? && (@conversation.bot_handoff_waiting? || @conversation.crm_delivery_pending?)
  end

  def fora_do_horario?
    @inbox.working_hours_enabled? && @inbox.out_of_office?
  end

  def horarios
    @horarios ||= @inbox.working_hours.index_by(&:day_of_week)
  end

  def quando(hora, atual: false)
    hora_texto = hora.strftime('%H:%M')
    dia = "#{DIAS_DA_SEMANA[hora.wday]}, #{hora.strftime('%d/%m')}"
    return "#{dia}, #{hora_texto}" if atual

    distancia = (hora.to_date - @agora.to_date).to_i
    relativo = { 0 => 'hoje', 1 => 'amanhã' }[distancia]
    relativo ? "#{relativo} (#{dia}) às #{hora_texto}" : "#{dia}, às #{hora_texto}"
  end
end
