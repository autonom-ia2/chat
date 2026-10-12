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
# de propósito); sem ele, ou com ele de agenda pausada em Meus horários, o primeiro link ativo de quem não pausou, como
# o convite (`InvitePages#link_for`).
#
# NADA AQUI LÊ O QUE A PESSOA ESCREVEU (RA-09). Quem entende "a de quarta" é o modelo; as ferramentas recebem data,
# horário ISO e duração e conferem por parser (`Date.iso8601`, `Time.iso8601`) e pelos limites da página.
#
# Toda recusa diz ao modelo o que fazer: pedir um dado, oferecer outras opções ou passar para uma pessoa pelo
# caminho que já existe (`should_handoff`, que entrega a conversa conforme a Atribuição do CRM).
#
# PÁGINA QUE NÃO MARCA (#1305): apagada, de outra conta, pausada ou sem ninguém para atender com o `booking_page_id`
# ainda gravado. O estado vem da MESMA regra do convite e da tela de páginas (`InvitePages#status`, via `estado`): as
# ferramentas somem do turno (`pode_marcar?`) e a instrução "# Agenda" diz que a agenda está indisponível e manda
# passar para uma pessoa, em vez de a IA prometer horário e cair na recusa. O `booking_page_id` não é apagado: o dono
# vê o estado na tela. Se a página mudar no meio do turno, a recusa da ferramenta traz o mesmo motivo, estruturado.
#
# PESSOAS LIBERADAS (#1307): o dono libera, na configuração do agente, quais pessoas da página a IA pode usar
# (`AgendaPessoas`, `config['booking_agent_ids']`; vazio = todas). Com quem marcar entre elas é decisão do MODELO,
# pela instrução do dono e pela conversa: `horarios_disponiveis` aceita `pessoa_id` (sem ele, junta as liberadas que
# podem atender, cada horário com a pessoa) e `agendar_reuniao` exige `pessoa_id` quando há mais de uma. O servidor
# confere a pessoa contra as liberadas, quem atende a página, a agenda dela e o horário livre dela (o `Booker`). A
# pessoa atribuída à conversa não decide mais sozinha: ela vai ao modelo (`quem_atende_esta_conversa`) como dado.
#
# MEMÓRIA DO TURNO (#1307): `pode_marcar?` (gate das duas ferramentas) e `instrucao` liam o estado da página três
# vezes por turno (até 3 `InvitePages`, cada um com a consulta de elegibilidade e a de pausas). `no_turno` guarda o
# estado por agente durante o turno (`Answerer#answer`); fora dele, nada é guardado. As ferramentas, ao rodar,
# sempre leem de novo (`estado_da_pagina`).
module Autonomia::Agents::Tools::Native::Agenda
  include Autonomia::Agents::Tools::Native::AgendaRespostas
  include Autonomia::Agents::Tools::Native::AgendaComQuem
  include Autonomia::Agents::Tools::Native::AgendaLocais

  SLUGS = %w[horarios_disponiveis agendar_reuniao].freeze
  CONFIG_KEY = 'booking_page_id'.freeze
  PESSOAS_KEY = ::Autonomia::Agents::Tools::Native::AgendaPessoas::CONFIG_KEY
  MAX_OPCOES = 6
  # Sem data pedida, no máximo dois horários por dia: as opções se espalham por dias diferentes.
  POR_DIA_SEM_DATA = 2
  DIAS_DA_SEMANA = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze

  # Estados da agenda (`estado`): os três de `InvitePages#status` e a página que não existe para o agente.
  ATIVA = ::Crm::BookingV2::InvitePages::ACTIVE
  PAUSADA_ESTADO = ::Crm::BookingV2::InvitePages::PAUSED
  SEM_RESPONSAVEL = ::Crm::BookingV2::InvitePages::NO_HOST
  AGENDA_PAUSADA = ::Crm::BookingV2::InvitePages::AGENDA_PAUSED
  PAGINA_INEXISTENTE = 'pagina_inexistente'.freeze
  SEM_HORARIO = 'sem_horario'.freeze

  PASSAR_PARA_PESSOA = 'Diga isso ao cliente com suas palavras, sem prometer horário, e passe a conversa para uma ' \
                       'pessoa da equipe: should_handoff=true, handoff_reason "agendamento indisponível".'.freeze
  SEM_PAGINA = "A agenda deste atendimento não está disponível agora. #{PASSAR_PARA_PESSOA}".freeze
  PAUSADA = "A página de agendamento está pausada. #{PASSAR_PARA_PESSOA}".freeze
  SEM_ATENDENTE = "A página de agendamento está sem ninguém para atender. #{PASSAR_PARA_PESSOA}".freeze
  AGENDA_DE_QUEM_ATENDE_PAUSADA = "Quem atende por esta agenda pausou os próprios horários. #{PASSAR_PARA_PESSOA}".freeze
  SEM_HORARIOS = "Não há horário livre na agenda nos próximos dias. #{PASSAR_PARA_PESSOA}".freeze
  SEM_HORARIOS_DA_PESSOA = 'Esta pessoa não tem horário livre nos próximos dias. Se houver outras pessoas liberadas, ' \
                           "chame de novo sem pessoa_id e ofereça os horários delas. Senão: #{PASSAR_PARA_PESSOA}".freeze

  def self.page_id(agent)
    agent.config.to_h[CONFIG_KEY].presence
  end

  # A página gravada no agente, só se for página nova DA CONTA DO AGENTE. Id de outra conta (forjado) ou apagado: nil.
  def self.pagina_de(agent)
    id = Integer(page_id(agent).to_s, exception: false)
    return if id.nil? || agent.account.nil?

    agent.account.crm_agent_booking_profiles.new_pages.find_by(id: id)
  end

  # 'ativa' | 'pausada' | 'sem_responsavel' | 'agenda_pausada' | 'pagina_inexistente'. A regra é a do convite
  # (`InvitePages#status`) e, com a página ativa, a das pessoas liberadas (`AgendaPessoas#estado`): sem liberada que
  # possa atender é 'sem_responsavel'; todas pausadas, 'agenda_pausada'. Dentro de `no_turno`, uma vez por agente.
  def self.estado(agent)
    chave = [agent.id, agent.config.to_h.slice(CONFIG_KEY, PESSOAS_KEY)]
    ::Autonomia::Agents::Tools::Native::AgendaDoTurno.lembrar(chave) { calcular_estado(agent) }
  end

  def self.calcular_estado(agent)
    pagina = pagina_de(agent)
    return PAGINA_INEXISTENTE if pagina.nil?

    paginas = ::Crm::BookingV2::InvitePages.new(agent.account)
    status = paginas.status(pagina)
    return status unless status == ATIVA

    ::Autonomia::Agents::Tools::Native::AgendaPessoas.new(agent: agent, pagina: pagina, paginas: paginas).estado
  end
  private_class_method :calcular_estado

  # O turno inteiro lê o estado uma vez por agente (gate das ferramentas e instrução). Aninhado, reaproveita.
  def self.no_turno(&)
    ::Autonomia::Agents::Tools::Native::AgendaDoTurno.no_turno(&)
  end

  # A agenda ligada E a página marcando agora: só aí as ferramentas entram no turno.
  def self.pode_marcar?(agent)
    disponivel?(agent) && estado(agent) == ATIVA
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
  # (o esqueleto antigo do tipo `scheduler` proibia consultar a agenda). Com a página sem marcar, a instrução diz isso.
  def self.instrucao(agent)
    return unless ligada?(agent)

    situacao = estado(agent)
    return ::Autonomia::Agents::Tools::Native::AgendaInstrucao.para(situacao) unless situacao == ATIVA

    pagina = pagina_de(agent)
    pessoas = ::Autonomia::Agents::Tools::Native::AgendaPessoas.new(
      agent: agent, pagina: pagina, paginas: ::Crm::BookingV2::InvitePages.new(agent.account)
    ).atendem
    ::Autonomia::Agents::Tools::Native::AgendaInstrucao.para(situacao, pessoas: pessoas, prazo_minutos: pagina.cancel_until_minutes)
  end

  private

  def pagina
    return @pagina if defined?(@pagina)

    @pagina = ::Autonomia::Agents::Tools::Native::Agenda.pagina_de(agent)
  end

  def paginas
    @paginas ||= ::Crm::BookingV2::InvitePages.new(account)
  end

  # O estado da página nesta chamada, pela mesma regra do turno (`Agenda.estado`), lido de novo (sem a memória do
  # turno). Agenda desligada na conta conta como página inexistente: não há agenda para a IA.
  def estado_da_pagina
    return PAGINA_INEXISTENTE if pagina.blank? || !::Crm::Config.booking_v2_enabled?(account)

    status = paginas.status(pagina)
    status == ATIVA ? pessoas.estado : status
  end

  # nil quando a página serve; senão a recusa (com o registro), com o motivo estruturado.
  def recusa_da_pagina
    case estado_da_pagina
    when ATIVA then nil
    when PAGINA_INEXISTENTE then recusar('agenda_sem_pagina', indisponivel(PAGINA_INEXISTENTE, SEM_PAGINA))
    when SEM_RESPONSAVEL then recusar('agenda_sem_responsavel', indisponivel(SEM_RESPONSAVEL, SEM_ATENDENTE))
    when AGENDA_PAUSADA then recusar('agenda_de_quem_atende_pausada', indisponivel(AGENDA_PAUSADA, AGENDA_DE_QUEM_ATENDE_PAUSADA))
    else recusar('agenda_pagina_pausada', indisponivel(PAUSADA_ESTADO, PAUSADA))
    end
  end

  def recusa_sem_horarios
    instrucao = params['pessoa_id'].nil? ? SEM_HORARIOS : SEM_HORARIOS_DA_PESSOA
    recusar('agenda_sem_horarios', indisponivel(SEM_HORARIO, instrucao))
  end

  # Data, horário, duração ou local fora do que a página oferece. Um código para os quatro; o texto diz qual.
  def parametro_invalido(texto)
    recusar('agenda_parametro_invalido', recusa_em_campos('parametro_invalido', texto))
  end

  def conversa
    conversation = delivery.try(:conversation)
    conversation if conversation.present? && conversation.account_id == account.id
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

  # Horários livres de `quem` (pessoas), do mesmo jeito que a página pública: o dia pedido, ou os próximos dias da
  # janela. -> [{ inicio:, pessoa: }].
  def horarios(dia:, duracao:, quem:)
    return livres_no_dia(dia, duracao, quem).first(MAX_OPCOES) if dia

    proximos_dias.each_with_object([]) do |data, opcoes|
      opcoes.concat(livres_no_dia(data, duracao, quem).first(POR_DIA_SEM_DATA))
      break opcoes if opcoes.size >= MAX_OPCOES
    end.first(MAX_OPCOES)
  end

  # Cada pessoa pela regra da página pública (`Slots`, com ela de responsável). Várias pessoas: junta pelo início; no
  # mesmo início fica a primeira na ordem da página (o modelo pede outra pelo `pessoa_id`).
  def livres_no_dia(dia, duracao, quem)
    todas = quem.flat_map { |pessoa| livres_da_pessoa(pessoa, dia, duracao) }
    todas.uniq { |opcao| opcao[:inicio] }.sort_by { |opcao| Time.iso8601(opcao[:inicio]) }
  end

  def livres_da_pessoa(pessoa, dia, duracao)
    livres = ::Crm::BookingV2::Slots.new(profile: pagina, host: pessoa.user, date: dia.iso8601, duration: duracao).perform
    livres.map { |iso| { inicio: iso, pessoa: pessoa } }
  end

  def proximos_dias
    hoje = Time.current.in_time_zone(fuso).to_date
    ultimo = hoje + [pagina.booking_window_days, ::Crm::BookingV2::Slots::MAX_SCAN_DAYS].min
    (hoje..ultimo).select { |dia| pagina.weekdays.include?(dia.wday) }
  end
end
