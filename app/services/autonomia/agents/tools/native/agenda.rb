# A AGENDA DA IA (#1196, F3): o que as duas ferramentas de agendamento (`horarios_disponiveis` e `agendar_reuniao`)
# têm em comum.
#
# A PÁGINA VEM SÓ DA CONFIGURAÇÃO DO AGENTE (`config['booking_page_id']`), nunca de parâmetro do modelo, e só vale
# página nova da MESMA conta: id de outra conta, página antiga ou apagada é "sem página". Escolher a página é o que
# liga as duas ferramentas (`Agent#ferramentas_nativas`); a flag da conta (`crm_booking_v2`) e o CRM ligado decidem
# se elas aparecem no turno (`disponivel?`). Agente cujas ferramentas são mantidas pelo deploy (o Agente de Cotação)
# não recebe a agenda: não aceita página (`aceita?`) e não recebe a instrução (`ligada?`).
#
# A REGRA DE HORÁRIO É A DA PÁGINA PÚBLICA (J6-A1): o mesmo `Crm::BookingV2::Slots`, com o mesmo responsável que a
# página atende. Página `per_agent`: o link de quem está atribuído à conversa (a Atribuição do CRM decide quem atende,
# de propósito); sem ele, o primeiro link ativo, como o convite (`InvitePages#link_for`).
#
# NADA AQUI LÊ O QUE A PESSOA ESCREVEU (RA-09). Quem entende "a de quarta" é o modelo; as ferramentas recebem data,
# horário ISO e duração e conferem por parser (`Date.iso8601`, `Time.iso8601`) e pelos limites da página.
#
# Toda recusa diz ao modelo o que fazer: pedir um dado, oferecer outras opções ou passar para uma pessoa pelo
# caminho que já existe (`should_handoff`, que entrega a conversa conforme a Atribuição do CRM).
module Autonomia::Agents::Tools::Native::Agenda
  SLUGS = %w[horarios_disponiveis agendar_reuniao].freeze
  CONFIG_KEY = 'booking_page_id'.freeze
  MAX_OPCOES = 6
  # Sem data pedida, no máximo dois horários por dia: as opções se espalham por dias diferentes.
  POR_DIA_SEM_DATA = 2
  DIAS_DA_SEMANA = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze

  PASSAR_PARA_PESSOA = 'Diga isso ao cliente com suas palavras, sem prometer horário, e passe a conversa para uma ' \
                       'pessoa da equipe: should_handoff=true, handoff_reason "agendamento indisponível".'.freeze
  SEM_PAGINA = "A agenda deste atendimento não está disponível agora. #{PASSAR_PARA_PESSOA}".freeze
  PAUSADA = "A página de agendamento está pausada ou sem ninguém para atender. #{PASSAR_PARA_PESSOA}".freeze
  SEM_HORARIOS = "Não há horário livre na agenda nos próximos dias. #{PASSAR_PARA_PESSOA}".freeze

  def self.page_id(agent)
    agent.config.to_h[CONFIG_KEY].presence
  end

  # As ferramentas nativas do agente com as da agenda, quando há página escolhida (`Agent#ferramentas_nativas`).
  def self.com_agenda(agent, slugs)
    page_id(agent).blank? ? slugs : (Array(slugs) + SLUGS).uniq
  end

  # O agente pode receber a agenda: as ferramentas dele não são as mantidas pelo deploy (Agente de Cotação).
  def self.aceita?(agent)
    ::Autonomia::Insurance::QuoteAgent::Builder.ferramentas_mantidas(agent).nil?
  end

  # Gravação da config (`Agent`): sem página, ou página nova da própria conta num agente que recebe a agenda. Só
  # confere quando a página MUDA: uma página apagada depois não pode travar o salvar das outras configurações (a
  # ferramenta recusa ao rodar).
  def self.pagina_valida?(agent)
    valor = page_id(agent)
    return true if valor.blank? || valor == agent.config_in_database.to_h[CONFIG_KEY]
    return false unless aceita?(agent)

    id = Integer(valor.to_s, exception: false)
    id.present? && agent.account.present? && agent.account.crm_agent_booking_profiles.new_pages.exists?(id: id)
  end

  # A página escolhida E a agenda ligada para a conta. Lido no gate do catálogo e no bloco do prompt.
  def self.disponivel?(agent)
    page_id(agent).present? && ::Crm::Config.enabled? && ::Crm::Config.booking_v2_enabled?(agent.account)
  end

  # A agenda ligada E as duas ferramentas no catálogo do agente: só aí a instrução fala delas.
  def self.ligada?(agent)
    disponivel?(agent) && (SLUGS - Array(agent.ferramentas_nativas)).empty?
  end

  # Instrução do turno quando o agente tem a agenda. Vale sobre a instrução escrita antes da ferramenta existir
  # (o esqueleto antigo do tipo `scheduler` proibia consultar a agenda).
  def self.instrucao(agent)
    return unless ligada?(agent)

    <<~TEXT.strip
      # Agenda
      Você tem a agenda deste atendimento e PODE oferecer horários e marcar reuniões. Isto vale sobre qualquer regra
      anterior que diga para só anotar a preferência ou nunca consultar a agenda.
      - Quando o cliente quiser marcar, chame `horarios_disponiveis` e ofereça 2 ou 3 opções, com dia da semana e hora.
      - Só ofereça horário que a ferramenta devolveu. NUNCA invente horário nem confirme sem a ferramenta.
      - Antes de marcar, confirme com o cliente o dia, a hora e o local. Depois chame `agendar_reuniao` com o horário
        exatamente como a ferramenta devolveu.
      - Só diga que está marcado quando `agendar_reuniao` confirmar.
      - Se a ferramenta recusar, siga o que ela disser: pedir um dado, oferecer as novas opções ou passar para uma pessoa.
    TEXT
  end

  private

  def pagina
    return @pagina if defined?(@pagina)

    id = Integer(::Autonomia::Agents::Tools::Native::Agenda.page_id(agent).to_s, exception: false)
    @pagina = id && account.crm_agent_booking_profiles.new_pages.find_by(id: id)
  end

  def paginas
    @paginas ||= ::Crm::BookingV2::InvitePages.new(account)
  end

  # nil quando a página serve; senão o texto da recusa (com o registro).
  def recusa_da_pagina
    return recusar('agenda_sem_pagina', SEM_PAGINA) if pagina.blank? || !::Crm::Config.booking_v2_enabled?(account)
    return recusar('agenda_pausada', PAUSADA) unless paginas.usable?(pagina)

    nil
  end

  def recusa_sem_horarios
    recusar('agenda_sem_horarios', SEM_HORARIOS)
  end

  # Data, horário, duração ou local fora do que a página oferece. Um código para os quatro; o texto diz qual.
  def parametro_invalido(texto)
    recusar('agenda_parametro_invalido', texto)
  end

  def conversa
    conversation = delivery.try(:conversation)
    conversation if conversation.present? && conversation.account_id == account.id
  end

  def link
    return @link if defined?(@link)

    @link = paginas.link_for(pagina, conversa&.assignee)
  end

  # O mesmo responsável do `Booker`: o do link individual ou o responsável padrão da página.
  def responsavel
    link&.agent || pagina.default_assignee
  end

  def fuso
    @fuso ||= ActiveSupport::TimeZone[pagina.resolved_timezone] || ActiveSupport::TimeZone['UTC']
  end

  # Duração pedida em minutos, ou a da página. nil quando o modelo pediu uma que a página não oferece.
  def duracao_pedida
    return @duracao_pedida if defined?(@duracao_pedida)

    valor = params['duracao_minutos']
    minutos = valor.nil? ? pagina.duration_minutes : Integer(valor.to_s, exception: false)
    @duracao_pedida = (minutos if pagina.durations.include?(minutos))
  end

  def duracao_invalida
    parametro_invalido("Essa duração não existe nesta agenda. Durações possíveis, em minutos: #{pagina.durations.join(', ')}.")
  end

  # Horários livres, do mesmo jeito que a página pública: o dia pedido, ou os próximos dias da janela.
  def horarios(dia:, duracao:)
    return livres_no_dia(dia, duracao).first(MAX_OPCOES) if dia

    proximos_dias.each_with_object([]) do |data, opcoes|
      opcoes.concat(livres_no_dia(data, duracao).first(POR_DIA_SEM_DATA))
      break opcoes if opcoes.size >= MAX_OPCOES
    end.first(MAX_OPCOES)
  end

  def livres_no_dia(dia, duracao)
    ::Crm::BookingV2::Slots.new(profile: pagina, host: responsavel, date: dia.iso8601, duration: duracao).perform
  end

  def proximos_dias
    hoje = Time.current.in_time_zone(fuso).to_date
    ultimo = hoje + [pagina.booking_window_days, ::Crm::BookingV2::Slots::MAX_SCAN_DAYS].min
    (hoje..ultimo).select { |dia| pagina.weekdays.include?(dia.wday) }
  end

  # "2026-10-20T10:00:00-03:00 (terça-feira, 20/10, 10:00)": o valor para devolver à ferramenta e o rótulo para falar.
  def opcao(iso)
    hora = Time.iso8601(iso).in_time_zone(fuso)
    "- #{iso} (#{DIAS_DA_SEMANA[hora.wday]}, #{hora.strftime('%d/%m, %H:%M')})"
  end

  def locais
    Array(pagina.locations).select { |item| item.is_a?(Hash) }
  end

  # Meet/Teams: o convite sai pelo provedor, que exige o e-mail do cliente (`Booker#validate_provider_location!`).
  def local_pede_email?(tipo)
    ::Crm::BookingPageSettings::CALENDAR_LOCATIONS.key?(tipo.to_s)
  end

  # O e-mail do contato da conversa; sem ele, o que o modelo mandou porque a ferramenta pediu. Dado, não texto de
  # pessoa: quem confere a forma é o `BookingInput` do Booker.
  def email_do_cliente
    conversa&.contact&.email.presence || params['email'].to_s.strip.presence
  end

  # Os locais que a IA oferece: na conversa de um cliente sem e-mail, só os que não precisam dele (se todos
  # precisam, todos, e a descrição avisa). Sem conversa (Testar), todos, como no atendimento de quem tem e-mail.
  def locais_oferecidos
    return locais if conversa.blank? || email_do_cliente.present?

    locais.reject { |local| local_pede_email?(local['type']) }.presence || locais
  end

  def rotulo_do_local(local)
    rotulo = ::Crm::BookingV2::LocationLabel.for(local, account: account) || local['type']
    local['address'].present? ? "#{rotulo}: #{local['address']}" : rotulo
  end

  def descricao_dos_locais
    locais_oferecidos.map { |local| "#{local['type']} (#{rotulo_do_local(local)}#{aviso_de_email(local)})" }.join('; ')
  end

  def aviso_de_email(local)
    conversa.present? && email_do_cliente.blank? && local_pede_email?(local['type']) ? ', pede o e-mail do cliente' : ''
  end
end
