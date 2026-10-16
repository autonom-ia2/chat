# A conversa espera uma pessoa e a equipe está fora do horário da caixa (#1691, decisão do Rodrigo de 16/10/2026). A IA
# segue atendendo (o modo do agente não muda) e passa a SABER disso: que a conversa espera alguém da equipe e quando a
# equipe volta, pela próxima abertura do horário de atendimento da caixa. Como dizer ao cliente fica com ela.
#
# "Espera uma pessoa" é o mesmo critério de Message#waiting_for_person?: a marca da passagem do robô (#1377) ou a do
# motor de entrega (#1454), sem pessoa no nome. "Fora do horário" e a hora da volta saem do HorarioDaCaixa, o mesmo
# leitor do EngagementGate: a IA nunca anuncia uma hora diferente da que o gate usa. Fuso: o da fonte (o calendário do
# CRM da caixa, ou `inbox.timezone`, que sem a flag `horario_unico_caixa` é o fuso gravado na caixa e, com ela, o da
# conta). Só com a Fase 2 (quem chama checa), para todo agente da conta, a Lia inclusive (decisão do Rodrigo, 16/10/2026,
# como no #1710).
#
# O instante é o relógio de agora (Time.current, lido uma vez pelo HorarioDaCaixa); nos specs, com travel_to.
class Autonomia::Agents::Operate::EsperaForaDoHorario
  DIAS_DA_SEMANA = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  SEM_DATA_DE_VOLTA = 'Esta caixa não tem dia de atendimento marcado: não há data de volta da equipe, e você não deve ' \
                      'inventar uma.'.freeze
  COMO_DIZER = 'Você decide se e como contar isso ao cliente. Se disser quando a equipe volta, não prometa que alguém ' \
               'responde nesse horário exato, não prometa resposta antes dele e não fale em nome da equipe. A hora que ' \
               'vale é a deste horário de atendimento: se outra mensagem da conversa citar outra hora, siga esta. ' \
               'Continue ajudando no que souber.'.freeze

  def initialize(conversation:)
    @conversation = conversation
    @horario = ::Autonomia::Agents::Operate::HorarioDaCaixa.new(conversation: conversation)
  end

  # O texto do contexto do turno, ou nil quando a conversa não espera pessoa ou a caixa está no horário (ou não tem
  # horário). Dia "aberto o dia todo" conta como aberto nas 24 horas: o WorkingHour#open_at? nem olha a hora.
  def texto
    return unless esperando_pessoa? && @horario.aberta_agora == false

    abertura = @horario.proxima_abertura
    volta = abertura ? "A equipe volta #{quando(abertura)}." : SEM_DATA_DE_VOLTA
    'SITUAÇÃO DESTA CONVERSA NESTE TURNO: o cliente está esperando alguém da equipe, e a equipe está fora do horário ' \
      "de atendimento agora (#{quando(@horario.local, atual: true)}). #{volta} #{COMO_DIZER}"
  end

  private

  def esperando_pessoa?
    @conversation.assignee_id.blank? && (@conversation.bot_handoff_waiting? || @conversation.crm_delivery_pending?)
  end

  def quando(hora, atual: false)
    hora_texto = hora.strftime('%H:%M')
    dia = "#{DIAS_DA_SEMANA[hora.wday]}, #{hora.strftime('%d/%m')}"
    return "#{dia}, #{hora_texto}" if atual

    distancia = (hora.to_date - @horario.local.to_date).to_i
    relativo = { 0 => 'hoje', 1 => 'amanhã' }[distancia]
    relativo ? "#{relativo} (#{dia}) às #{hora_texto}" : "#{dia}, às #{hora_texto}"
  end
end
