# MARCA A REUNIÃO que o cliente escolheu na conversa (#1196, F3, J6-A3/A4).
#
# Síncrona: roda no turno e precisa da conversa (`delivery`); no Testar, Copiloto e playground recusa com nome.
# Reserva pelo MESMO `Crm::BookingV2::Booker` da página pública: travas de caixa, agente e telefone, reconferência do
# horário dentro delas, contato e card. `source: 'ai'` marca a reunião (e o card, se nascer agora) como da IA.
#
# Quem é o cliente vem da conversa, nunca do modelo: o contato dela, com o telefone dele. O modelo só manda
# `telefone` quando o contato não tem um número válido e o cliente o informou. O card é o que a conversa já tem
# aberto (`ConversationCardFinder`, o mesmo do "criar card da conversa"); sem ele, o Booker cria um na conversa.
# Na mesma transação nasce um convite `channel: 'ai'` com a reunião: o link de gestão e a conversa ficam no mesmo
# mecanismo da reserva pela página (F1-C).
#
# Horário tomado entre a oferta e a escolha (outro cliente, outra conversa): devolve NOVAS opções, nunca reserva
# dupla (a trava do agente decide quem fica). A chave de idempotência é a do turno: o retry do mesmo turno devolve a
# mesma reunião; outro turno pedindo o mesmo horário é outro pedido.
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
          'description' => 'Só quando a ferramenta pediu: o número que o cliente informou, com DDD. Senão null.' }
      ]
    end

    # O horário e a duração ajudam o diagnóstico; o telefone, nunca.
    def args_registraveis
      %w[inicio duracao_minutos local]
    end

    def available_for?(agent)
      Autonomia::Agents::Tools::Native::Agenda.disponivel?(agent)
    end
  end

  def call
    return recusar('agenda_sem_conversa', SEM_CONVERSA) if conversa.blank?

    recusa = recusa_da_pagina
    return recusa if recusa

    duracao = duracao_pedida
    return duracao_invalida if duracao.nil?
    return parametro_invalido(INICIO_INVALIDO) if inicio.nil?
    return recusar('agenda_sem_telefone', SEM_TELEFONE) if telefone.blank?

    reservar(duracao)
  end

  private

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

  def reservar(duracao)
    resultado = ActiveRecord::Base.transaction do
      reserva = booker(duracao).perform
      convite!(reserva)
      reserva
    end
    confirmar(resultado.meeting)
  rescue ArgumentError => e
    tratar_erro(e.message, duracao)
  end

  def booker(duracao)
    ::Crm::BookingV2::Booker.new(
      profile: pagina, name: contato.name.presence || telefone, phone: telefone, starts_at: inicio.iso8601,
      duration: duracao, location_type: params['local'].presence, source: SOURCE, conversation: conversa, link: link,
      contact: contato, card: card_da_conversa, idempotency_key: chave_da_tentativa
    )
  end

  # O retry do mesmo turno é a mesma tentativa; outro turno, ou outro horário, é outra.
  def chave_da_tentativa
    "ai:#{conversa.id}:#{delivery.turno}:#{inicio.utc.iso8601}"
  end

  def card_da_conversa
    card = ::Crm::Cards::ConversationCardFinder.new(account: account).find(conversa)
    card if card&.open? && card.contact_id == contato&.id
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
    return novas_opcoes(duracao) if codigo == 'slot_unavailable'
    return parametro_invalido(texto_do_parametro(codigo)) if ERROS_DE_PARAMETRO.include?(codigo)
    return recusar('agenda_limite_de_reunioes', LIMITE) if codigo == 'too_many_open'

    Rails.logger.warn("[autonomia][agenda] reserva recusada account=#{account.id} codigo=#{codigo}")
    recusar('agenda_indisponivel', INDISPONIVEL)
  end

  def texto_do_parametro(codigo)
    return "Esse local não existe nesta agenda. Locais possíveis: #{descricao_dos_locais}. Nada foi marcado." if codigo == 'invalid_location'

    INICIO_INVALIDO
  end

  # O dia pedido primeiro; sem vaga nele, os próximos.
  def novas_opcoes(duracao)
    opcoes = horarios(dia: inicio.in_time_zone(fuso).to_date, duracao: duracao).presence || horarios(dia: nil, duracao: duracao)
    return recusa_sem_horarios if opcoes.empty?

    recusar('agenda_horario_ocupado', [OCUPADO, *opcoes.map { |iso| opcao(iso) }].join("\n"))
  end
end
