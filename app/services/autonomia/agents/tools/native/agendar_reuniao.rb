# MARCA A REUNIÃO que o cliente escolheu na conversa (#1196, F3, J6-A3/A4).
#
# Síncrona: roda no turno e precisa da conversa (`delivery`); no Testar, Copiloto e playground recusa com nome.
# Reserva pelo MESMO `Crm::BookingV2::Booker` da página pública: travas de caixa, agente e telefone, reconferência do
# horário dentro delas, contato e card. `source: 'ai'` marca a reunião (e o card, se nascer agora) como da IA.
#
# Quem é o cliente vem da conversa, nunca do modelo: o contato dela, com o telefone dele. O modelo só manda
# `telefone` quando o contato não tem um número válido e o cliente o informou. O card é o que a conversa já tem
# aberto (`ConversationCardFinder`, o mesmo do "criar card da conversa"); sem ele, o Booker cria um na conversa.
# Junto com a reunião, no bloco que o Booker roda na transação dele e sob as travas (`perform { ... }`), nascem o
# convite `channel: 'ai'` (o link de gestão e a conversa ficam no mesmo mecanismo da reserva pela página, F1-C) e, se
# o card nasceu agora sem a conversa (contato sem telefone: Instagram, webchat), o vínculo do card com ESTA conversa.
# A consulta ao provedor roda fora de transação, como na página pública.
#
# Meet/Teams mandam o convite pelo provedor e exigem e-mail: vai o do contato, ou o que o cliente informou quando o
# contato não tem. Sem e-mail, esses locais nem são oferecidos (`locais_oferecidos`) e, pedidos assim mesmo, a
# ferramenta pede o e-mail.
#
# Horário tomado entre a oferta e a escolha (outro cliente, outra conversa): devolve NOVAS opções, nunca reserva
# dupla (a trava do agente decide quem fica). A chave de idempotência é a do turno: o retry do mesmo turno devolve a
# mesma reunião. Outro turno pedindo o mesmo horário é outro pedido, mas se quem ocupa o horário é a reunião deste
# mesmo cliente nesta página, a ferramenta confirma essa reunião em vez de dizer que o horário foi ocupado.
# Turno acionado por evento (aviso do sistema) não marca: não é pedido do cliente.
class Autonomia::Agents::Tools::Native::AgendarReuniao < Autonomia::Agents::Tools::Native::Base
  include Autonomia::Agents::Tools::Native::Agenda

  SOURCE = 'ai'.freeze
  SEM_CONVERSA = 'Só dá para marcar dentro de uma conversa com o cliente. Aqui não há conversa: diga que a marcação ' \
                 'acontece no atendimento real.'.freeze
  SEM_TELEFONE = 'O contato não tem um telefone válido. Peça ao cliente o número com DDD e chame de novo com ' \
                 '`telefone`. Nada foi marcado.'.freeze
  INICIO_INVALIDO = 'O horário precisa ser um dos que `horarios_disponiveis` devolveu, exatamente como veio. Nada foi ' \
                    'marcado.'.freeze
  OCUPADO = 'Esse horário acabou de ser ocupado e NÃO foi marcado. Peça desculpas e ofereça estas novas opções:'.freeze
  LIMITE = 'O cliente já tem reuniões marcadas demais nesta agenda e esta NÃO foi marcada. Explique e passe a conversa ' \
           'para uma pessoa da equipe: should_handoff=true, handoff_reason "cliente com reuniões em aberto".'.freeze
  SEM_EMAIL = 'Esse local manda o convite por e-mail e o cliente não tem e-mail no cadastro. Peça o e-mail ao ' \
              'cliente e chame de novo com `email`, ou ofereça outro local. Nada foi marcado.'.freeze
  EMAIL_INVALIDO = 'O e-mail informado não é válido. Peça de novo ao cliente. Nada foi marcado.'.freeze
  TURNO_DE_EVENTO = 'Este turno é um aviso do sistema, não um pedido do cliente: não marque nada agora. Se o ' \
                    'cliente quiser marcar, ele vai pedir na conversa.'.freeze
  INDISPONIVEL = "Não foi possível marcar agora e nada foi marcado. #{Autonomia::Agents::Tools::Native::Agenda::PASSAR_PARA_PESSOA}".freeze
  ERROS_DE_PARAMETRO = %w[invalid_starts_at invalid_duration invalid_location].freeze

  class << self
    def slug
      'agendar_reuniao'
    end

    def tool_name
      'Agendar reunião'
    end

    def description
      'Marca a reunião no horário que o cliente escolheu, entre os devolvidos por horarios_disponiveis. Use só ' \
        'depois de o cliente confirmar dia, hora e local. O cliente é o desta conversa.'
    end

    def params
      [
        { 'name' => 'inicio', 'type' => 'string',
          'description' => 'Início escolhido, exatamente como horarios_disponiveis devolveu (ISO 8601 com fuso).' },
        { 'name' => 'duracao_minutos', 'type' => 'integer', 'required' => false,
          'description' => 'A mesma duração usada na consulta. null usa a duração padrão.' },
        { 'name' => 'local', 'type' => 'string', 'required' => false,
          'description' => 'Tipo do local escolhido, entre os locais possíveis da consulta. null usa o primeiro.' },
        { 'name' => 'telefone', 'type' => 'string', 'required' => false,
          'description' => 'Só quando a ferramenta pediu: o número que o cliente informou, com DDD. Senão null.' },
        { 'name' => 'email', 'type' => 'string', 'required' => false,
          'description' => 'Só quando a ferramenta pediu: o e-mail que o cliente informou. Senão null.' }
      ]
    end

    # O horário e a duração ajudam o diagnóstico; o telefone e o e-mail, nunca.
    def args_registraveis
      %w[inicio duracao_minutos local]
    end

    def available_for?(agent)
      Autonomia::Agents::Tools::Native::Agenda.disponivel?(agent)
    end
  end

  def call
    return recusar('agenda_sem_conversa', SEM_CONVERSA) if conversa.blank?
    return recusar('agenda_turno_de_evento', TURNO_DE_EVENTO) if delivery.try(:turno_de_evento?)

    recusa = recusa_da_pagina || recusa_do_pedido
    return recusa if recusa

    reservar(duracao_pedida)
  end

  private

  # nil quando o pedido serve para reservar; senão o texto da recusa.
  def recusa_do_pedido
    return duracao_invalida if duracao_pedida.nil?
    return parametro_invalido(INICIO_INVALIDO) if inicio.nil?
    return recusar('agenda_sem_telefone', SEM_TELEFONE) if telefone.blank?
    return recusar('agenda_sem_email', SEM_EMAIL) if falta_email?

    nil
  end

  def inicio
    return @inicio if defined?(@inicio)

    @inicio = begin
      Time.iso8601(params['inicio'].to_s)
    rescue ArgumentError
      nil
    end
  end

  def contato
    conversa.contact
  end

  # O do contato; o informado só quando o contato não tem um válido. Sempre normalizado pela biblioteca de telefone.
  def telefone
    @telefone ||= normalizar(contato&.phone_number).presence || normalizar(params['telefone']).presence
  end

  def normalizar(numero)
    return if numero.blank?

    ::Crm::BookingV2::PhoneLookup.normalize(numero, region: ::Crm::BookingV2::PhoneLookup.region_for(pagina.resolved_timezone))
  end

  # O bloco roda só com a reserva NOVA, dentro da transação do Booker e sob as travas: convite e vínculo entram ou
  # saem junto com a reunião. O reenvio do mesmo turno devolve a reunião que já tem os dois.
  def reservar(duracao)
    reserva = booker(duracao).perform do |nova|
      vincular_card_a_conversa!(nova.card)
      convite!(nova)
    end
    confirmar(reserva.meeting)
  rescue ArgumentError => e
    tratar_erro(e.message, duracao)
  end

  def booker(duracao)
    ::Crm::BookingV2::Booker.new(
      profile: pagina, name: contato.name.presence || telefone, phone: telefone, starts_at: inicio.iso8601,
      duration: duracao, location_type: tipo_do_local, source: SOURCE, conversation: conversa, link: link,
      contact: contato, card: card_da_conversa, idempotency_key: chave_da_tentativa,
      email: local_pede_email?(tipo_do_local) ? email_do_cliente : nil
    )
  end

  # O local pedido; sem pedido, o primeiro dos oferecidos (sem e-mail, o primeiro que não precisa dele).
  def tipo_do_local
    params['local'].presence || locais_oferecidos.first&.dig('type')
  end

  # Local desta página que manda o convite por e-mail, sem e-mail do cliente. Local que a página não tem fica para o
  # Booker recusar (`invalid_location`), com a lista dos locais.
  def falta_email?
    local_pede_email?(tipo_do_local) && email_do_cliente.blank? && locais.any? { |local| local['type'] == tipo_do_local }
  end

  # O retry do mesmo turno é a mesma tentativa; outro turno, ou outro horário, é outra.
  def chave_da_tentativa
    "ai:#{conversa.id}:#{delivery.turno}:#{inicio.utc.iso8601}"
  end

  def card_da_conversa
    card = ::Crm::Cards::ConversationCardFinder.new(account: account).find(conversa)
    card if card&.open? && card.contact_id == contato&.id
  end

  # Card que nasceu agora sem conversa (o Booker só liga a conversa cujo contato tem o telefone da reserva): a IA
  # sabe de que conversa veio o pedido e liga o card a ela pelo mesmo vínculo do "vincular conversa" do card.
  def vincular_card_a_conversa!(card)
    return if card.conversation_id.present? || card.contact_id != conversa.contact_id

    ::Crm::Cards::ConversationLinker.new(card: card, conversation: conversa, actor: nil).link
  end

  def convite!(reserva)
    return if ::Crm::BookingInvite.exists?(meeting_id: reserva.meeting.id)

    ::Crm::BookingInvite.create!(
      account: account, booking_profile: pagina, booking_link: link, contact: reserva.contact, card: reserva.card,
      conversation: reserva.contact.id == conversa.contact_id ? conversa : nil, meeting: reserva.meeting, channel: SOURCE,
      scheduled_at: Time.current, expires_at: reserva.meeting.ends_at + ::Crm::BookingInvite::MANAGE_GRACE
    )
  end

  def confirmar(reuniao)
    hora = reuniao.starts_at.in_time_zone(fuso)
    local = reuniao.metadata.to_h['location'].to_h
    "Reunião marcada: #{DIAS_DA_SEMANA[hora.wday]}, #{hora.strftime('%d/%m, %H:%M')} (fuso #{fuso.tzinfo.name}), " \
      "#{((reuniao.ends_at - reuniao.starts_at) / 60).round} minutos, #{rotulo_do_local(local)}. Confirme ao cliente " \
      'o dia, a hora e o local. Não diga que mandou convite por e-mail.'
  end

  def tratar_erro(codigo, duracao)
    return ocupado(duracao) if codigo == 'slot_unavailable'
    return parametro_invalido(texto_do_parametro(codigo)) if ERROS_DE_PARAMETRO.include?(codigo)
    return parametro_invalido(EMAIL_INVALIDO) if codigo == 'invalid_email'
    return recusar('agenda_limite_de_reunioes', LIMITE) if codigo == 'too_many_open'

    Rails.logger.warn("[autonomia][agenda] reserva recusada account=#{account.id} codigo=#{codigo}")
    recusar('agenda_indisponivel', INDISPONIVEL)
  end

  def texto_do_parametro(codigo)
    return "Esse local não existe nesta agenda. Locais possíveis: #{descricao_dos_locais}. Nada foi marcado." if codigo == 'invalid_location'

    INICIO_INVALIDO
  end

  # Quem ocupa o horário pode ser a reunião deste mesmo cliente, marcada em outro turno: essa é confirmada.
  def ocupado(duracao)
    reuniao = reuniao_do_cliente_no_horario
    reuniao ? confirmar(reuniao) : novas_opcoes(duracao)
  end

  # Só dados do servidor: o contato desta conversa, esta página e o início pedido.
  def reuniao_do_cliente_no_horario
    ::Crm::Meeting.where(account_id: account.id, status: :scheduled, starts_at: inicio)
                  .where('crm_meetings.metadata @> ?', { booking_profile_id: pagina.id }.to_json)
                  .joins(:card).find_by(crm_cards: { contact_id: contato.id })
  end

  # O dia pedido primeiro; sem vaga nele, os próximos.
  def novas_opcoes(duracao)
    opcoes = horarios(dia: inicio.in_time_zone(fuso).to_date, duracao: duracao).presence || horarios(dia: nil, duracao: duracao)
    return recusa_sem_horarios if opcoes.empty?

    recusar('agenda_horario_ocupado', [OCUPADO, *opcoes.map { |iso| opcao(iso) }].join("\n"))
  end
end
