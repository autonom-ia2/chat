# O MAPA E O CARTÃO DE CONTATO DA PÁGINA DE AGENDAMENTO (#1479 F3): o que `enviar_localizacao` e `enviar_contato` têm em
# comum.
#
# A PÁGINA É A DA AGENDA (`Agenda.pagina_de`: `config['booking_page_id']`, página nova da própria conta). O dado vem
# dela e nunca do modelo: o endereço e a coordenada de um local presencial (a coordenada é do servidor, gravada pelo
# `Crm::BookingV2::GeocodificarLocaisJob`) e o `contact_phone`. Nunca o telefone de uma pessoa da equipe.
#
# ZERO CONFIGURAÇÃO, como a agenda: com a Fase 2 e a flag `agentes_enviar_local_e_contato`, o agente que tem página
# ganha os dois slugs (`com_cartoes`, lido por `Agent#ferramentas_nativas`), e cada ferramenta só entra no turno quando
# a página tem o dado dela (`available_for?`). A Lia (`insurance_quote`) fica fora: a lista dela é a do deploy.
#
# O TELEFONE DO AGENTE VEM PRIMEIRO (#1479, bloco "Endereço e telefone"): o cartão de contato leva o
# `config['atendimento']['telefone']` do agente e, sem ele, o `contact_phone` da página (`contato_do_agente`). O agente
# sem página mas com telefone ganha só `enviar_contato`, com o nome da conta no cartão. O endereço do agente nunca vira
# mapa: o mapa continua só dos locais presenciais da página. Quem resolve o cartão na hora de postar
# (`Operate::CartoesDoTurno.resolver`) passa pela mesma função, com a mesma ordem.
#
# AS FERRAMENTAS NÃO MANDAM NADA: marcam o cartão no contexto do turno (`Delivery#marcar_cartao`), e o Responder o manda
# numa mensagem própria, DEPOIS do texto (`Operate::CartoesDoTurno`). O cartão já sai no formato que o tipo aceita
# (`RichMessages::Types::Location` e `Contact`, conferidos aqui): o que não passa não é oferecido.
#
# NADA AQUI LÊ O QUE A PESSOA ESCREVEU. O modelo escolhe o local por um id da lista fechada (`local_id`, enum).
module Autonomia::Agents::Tools::Native::CartaoDaPagina
  FLAG = 'agentes_enviar_local_e_contato'.freeze
  SLUGS = %w[enviar_localizacao enviar_contato].freeze
  LIA = 'insurance_quote'.freeze
  PRESENCIAL = 'in_person'.freeze
  DIGITOS = '0123456789'.freeze
  # O id de um local é o começo do digest do endereço: não muda quando a ordem da lista muda, e um endereço trocado
  # entre o catálogo e a chamada vira id inválido (recusa com a lista), em vez de um mapa de outro lugar.
  TAMANHO_DO_ID = 8
  # A chave do cartão de contato. Fica 'pagina' também quando o telefone é o do agente (#1479): o token já gravado nas
  # âncoras e nas referências em voo continua resolvendo, e o cartão é um só por turno.
  CHAVE_DO_CONTATO = 'pagina'.freeze

  module_function

  # A Fase 2 e a flag da conta.
  def ligado?(account)
    account.present? && ::Autonomia::Agents::Fase2.ligada?(account) && account.feature_enabled?(FLAG)
  end

  # As ferramentas nativas do agente com os dois slugs, quando a conta está ligada e o agente tem página; sem página,
  # só `enviar_contato`, quando o agente tem telefone (`Agent#ferramentas_nativas`). Sem banco: o dado é conferido no
  # gate de cada ferramenta.
  def com_cartoes(agent, slugs)
    extras = slugs_extras(agent)
    return slugs if extras.empty? || !ligado?(agent.account)

    (Array(slugs) + extras).uniq
  end

  def slugs_extras(agent)
    return [] if agent.agent_type == LIA
    return SLUGS if ::Autonomia::Agents::Tools::Native::Agenda.page_id(agent).present?

    telefone_do_agente(agent) ? [SLUGS.last] : []
  end

  # A página do agente, só com a conta ligada e fora da Lia; senão nil. Quem monta o catálogo passa por aqui: a página
  # com endereço presencial ainda sem coordenada (a que existia antes da flag) pede o job (`GeocodificarLocaisJob.pedir`,
  # uma vez por página e pendentes), e o mapa entra no catálogo de um turno seguinte. Sem pendente, nem o Redis é lido.
  def pagina(agent)
    return if agent.agent_type == LIA || !ligado?(agent.account)

    ::Autonomia::Agents::Tools::Native::Agenda.pagina_de(agent).tap { |pagina| pedir_coordenada(pagina) }
  end

  # Erro ao pedir não derruba o catálogo: o log leva só o id da página e a classe, e o erro vai ao tracker.
  def pedir_coordenada(pagina)
    return if pagina.nil? || pagina.enderecos_sem_coordenada.empty?

    ::Crm::BookingV2::GeocodificarLocaisJob.pedir(pagina)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][cartao_da_pagina] geocodificar_nao_pedido page_id=#{pagina.id} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: pagina.account).capture_exception
  end

  # Os locais presenciais da página que viram mapa: com endereço e coordenada válida, sem repetir endereço.
  # -> [{ 'id', 'rotulo', 'endereco', 'rich_message' }]
  def locais(pagina)
    return [] if pagina.nil?

    Array(pagina.locations).filter_map { |item| local(item, pagina.account) }.uniq { |item| item['id'] }
  end

  def local(item, account)
    return unless item.is_a?(Hash) && item['type'] == PRESENCIAL

    endereco = item['address'].to_s.squish
    return if endereco.blank?

    rotulo = ::Crm::BookingV2::LocationLabel.for(item, account: account).to_s.squish
    formato = { 'type' => 'location', 'latitude' => item['latitude'], 'longitude' => item['longitude'],
                'name' => rotulo.first(::RichMessages::Types::Location::NAME_MAX).presence,
                'address' => endereco.first(::RichMessages::Types::Location::ADDRESS_MAX) }.compact
    return unless ::RichMessages::Types::Location.new(formato).error_for('').nil?

    { 'id' => id_do_local(endereco), 'rotulo' => rotulo.presence || endereco, 'endereco' => endereco, 'rich_message' => formato }
  end

  def id_do_local(endereco)
    Digest::SHA256.hexdigest(endereco).first(TAMANHO_DO_ID)
  end

  # O cartão de contato do agente: o telefone do agente (`config['atendimento']`) e, só quando ele falta, o da página.
  # Com o telefone do agente preenchido, nunca cai no da página (se ele não servir, nil). O nome é o título da página ou
  # o nome da conta; sem página, o nome da conta. Só com a conta ligada e fora da Lia; senão nil.
  # `pagina`: a de `pagina(agent)`, quando quem chama já a tem. Sem ela: com o telefone do agente, só lê a página para o
  # nome (`Agenda.pagina_de`, sem pedir coordenada); sem ele, `pagina(agent)`, como o cartão da página sempre fez.
  def contato_do_agente(agent, pagina = :buscar)
    return if agent.agent_type == LIA || !ligado?(agent.account)

    telefone = telefone_do_agente(agent)
    if telefone
      pagina = ::Autonomia::Agents::Tools::Native::Agenda.pagina_de(agent) if pagina == :buscar
      return cartao_de_contato(nome_do_cartao(pagina, agent.account), telefone)
    end

    contato(pagina == :buscar ? pagina(agent) : pagina)
  end

  # O telefone do agente com "+" e só os dígitos; nil quando está vazio. Preenchido sem "+" (gravado por fora da
  # validação) vira "" e o cartão não sai: nunca cai no da página.
  def telefone_do_agente(agent)
    valor = agent.dados_do_atendimento['telefone'].strip
    return if valor.empty?

    telefone(valor) || ''
  end

  # O cartão de contato da página: o nome (o título da página ou o nome da conta, até 100; nunca o nome público, que pode
  # ser o de uma pessoa da equipe) e o `contact_phone` com "+" e só os dígitos. nil quando o telefone ou o nome não servem
  # para o tipo.
  def contato(pagina)
    return if pagina.nil?

    cartao_de_contato(nome_do_cartao(pagina, pagina.account), telefone(pagina.contact_phone))
  end

  def nome_do_cartao(pagina, account)
    (pagina&.title.presence || account.name).to_s.squish.first(::RichMessages::Types::Contact::NAME_MAX)
  end

  # nil quando o telefone falta ou o cartão não passa no tipo.
  def cartao_de_contato(nome, telefone)
    return if telefone.nil?

    formato = { 'type' => 'contact', 'name' => nome, 'phone' => telefone }
    formato if ::RichMessages::Types::Contact.new(formato).error_for('').nil?
  end

  # "+55 (11) 4000-0473" -> "+551140000473". Só o que começa com "+"; os outros caracteres saem pela lista de dígitos.
  def telefone(valor)
    texto = valor.to_s.strip
    return unless texto.start_with?('+')

    "+#{texto.each_char.select { |caractere| DIGITOS.include?(caractere) }.join}"
  end

  # O que o Responder recebe do turno (`Delivery#marcar_cartao`). `chave` separa dois cartões do mesmo tipo.
  def cartao(tipo, chave, formato)
    { 'tipo' => tipo, 'chave' => chave, 'rich_message' => formato }
  end
end
