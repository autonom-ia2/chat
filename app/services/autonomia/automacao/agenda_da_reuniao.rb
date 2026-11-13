# A agenda do passo "Marcar reunião pela conversa" (#2935): os 3 horários livres que ele oferece e a reserva do
# escolhido. Tudo pela agenda que o CRM já tem (#1188), sem regra nova de horário:
#
# - a página: a mesma do link da agenda (LinkDaAgenda.pagina_de), a única página publicada em que a pessoa atende. Nunca
#   a de outra pessoa: o cliente marcaria com quem não é o responsável dele (parecer do Funções no G12);
# - os horários: os da página pública (Crm::BookingV2::Slots, com a pessoa de responsável): feriados, "Meus horários",
#   intervalos, antecedência, a janela da página e as reuniões que ela já tem. No máximo dois por dia, para as opções se
#   espalharem, como a agenda da IA;
# - a reserva: o mesmo Crm::BookingV2::Booker da página, do painel e da IA, com as mesmas travas. Dois clientes que
#   escolhem o mesmo horário não ficam com ele: o segundo recebe `slot_unavailable`. A reunião cai no card do contato
#   (o do alvo, se for dele e estiver aberto), com o convite da conversa e os avisos e lembretes da página
#   (BookingNotices), como a reunião que a IA marca.
class Autonomia::Automacao::AgendaDaReuniao
  OFERTAS = 3
  POR_DIA = 2
  # A reunião que nasce aqui: pela conversa, com o link de gestão do convite, e o cliente avisado (ele escolheu o horário).
  ORIGEM = 'invite'.freeze
  CANAL = 'conversation'.freeze
  BASE_DO_AVISO = 'escolhido_na_conversa_com_automacao'.freeze

  attr_reader :pagina, :por

  # `pessoa`: em qual agenda (User). `duracao`: em minutos; fora das durações da página, a padrão dela.
  def initialize(conta, pessoa, duracao)
    @conta = conta
    @pessoa = pessoa
    @pagina, @link, @por = ::Autonomia::Automacao::LinkDaAgenda.pagina_de(conta, pessoa)
    @duracao = duracao if @pagina&.durations.to_a.include?(duracao)
  end

  # Os próximos horários livres (Time, no fuso da página), até OFERTAS.
  def horarios
    return [] unless @pagina

    dias.each_with_object([]) do |dia, livres|
      livres.concat(livres_no_dia(dia).first(POR_DIA))
      break livres if livres.size >= OFERTAS
    end.first(OFERTAS)
  end

  # O horário como o cliente lê, no fuso da página e no idioma da conta: "Qui 13/11 10:00". O dia da semana vem do nosso
  # catálogo: o pt_BR da plataforma não tem os nomes dos dias do rails-i18n (que é pt-BR).
  def rotulo(inicio)
    hora = inicio.in_time_zone(fuso)
    I18n.with_locale(@conta.locale) do
      I18n.t('autonomia.automacao.valores.horario_da_reuniao', dia: I18n.t('autonomia.automacao.valores.dias_curtos')[hora.wday],
                                                               data: hora.strftime(I18n.t('autonomia.automacao.valores.data_curta')))
    end
  end

  # Reserva `inicio` para o contato. Levanta ArgumentError com o código do Booker (`slot_unavailable` na corrida).
  def marcar(inicio, contato:, card:, conversa:, chave:)
    reserva = booker(inicio, contato, card, conversa, chave).perform do |nova|
      registrar_aviso!(nova.meeting, conversa)
      convite!(nova, conversa)
    end
    convite = ::Crm::BookingInvite.where(meeting_id: reserva.meeting.id, channel: CANAL).order(:id).last
    ::Crm::BookingV2::BookingNotices.new(meeting: reserva.meeting, invite: convite).schedule
    reserva.meeting
  end

  private

  def fuso = ActiveSupport::TimeZone[@pagina.resolved_timezone.to_s] || Time.zone

  def dias
    hoje = Time.current.in_time_zone(fuso).to_date
    ultimo = hoje + [@pagina.booking_window_days.to_i, ::Crm::BookingV2::Slots::MAX_SCAN_DAYS].min
    (hoje..ultimo).select { |dia| Array(@pagina.weekdays).include?(dia.wday) }
  end

  def livres_no_dia(dia)
    livres = ::Crm::BookingV2::Slots.new(profile: @pagina, host: @pessoa, date: dia.iso8601, duration: @duracao).perform
    livres.map { |iso| Time.iso8601(iso) }
  end

  def booker(inicio, contato, card, conversa, chave)
    ::Crm::BookingV2::Booker.new(
      profile: @pagina, name: contato.name.presence || contato.phone_number.to_s, phone: contato.phone_number.to_s,
      starts_at: inicio.iso8601, duration: @duracao, location_type: local(contato), source: ORIGEM, conversation: conversa,
      link: @link, contact: contato, card: card, idempotency_key: chave, email: contato.email.presence
    )
  end

  # O primeiro local da página; sem e-mail do cliente, o primeiro que não pede e-mail (Meet e Teams pedem).
  def local(contato)
    locais = Array(@pagina.locations).select { |item| item.is_a?(Hash) }
    sem_email = locais.reject { |item| ::Crm::BookingPageSettings::CALENDAR_LOCATIONS.key?(item['type'].to_s) }
    (contato.email.present? ? locais : sem_email.presence || locais).first&.dig('type')
  end

  def registrar_aviso!(reuniao, conversa)
    reuniao.update!(metadata: reuniao.metadata.to_h.merge('notify_client' => true, 'notice_basis' => BASE_DO_AVISO,
                                                          'booked_in_conversation_id' => conversa&.id))
  end

  def convite!(reserva, conversa)
    return if ::Crm::BookingInvite.exists?(meeting_id: reserva.meeting.id)

    ::Crm::BookingInvite.create!(
      account: @conta, booking_profile: @pagina, booking_link: @link, contact: reserva.contact, card: reserva.card,
      conversation: conversa&.contact_id == reserva.contact.id ? conversa : nil, meeting: reserva.meeting, channel: CANAL,
      scheduled_at: Time.current, expires_at: reserva.meeting.ends_at + ::Crm::BookingInvite::MANAGE_GRACE
    )
  end
end
