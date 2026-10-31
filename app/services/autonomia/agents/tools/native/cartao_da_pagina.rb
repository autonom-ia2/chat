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
  CHAVE_DO_CONTATO = 'pagina'.freeze

  module_function

  # A Fase 2 e a flag da conta.
  def ligado?(account)
    account.present? && ::Autonomia::Agents::Fase2.ligada?(account) && account.feature_enabled?(FLAG)
  end

  # As ferramentas nativas do agente com os dois slugs, quando a conta está ligada e o agente tem página
  # (`Agent#ferramentas_nativas`). Sem banco: o dado da página é conferido no gate de cada ferramenta.
  def com_cartoes(agent, slugs)
    return slugs unless agent.agent_type != LIA && ::Autonomia::Agents::Tools::Native::Agenda.page_id(agent).present?
    return slugs unless ligado?(agent.account)

    (Array(slugs) + SLUGS).uniq
  end

  # A página do agente, só com a conta ligada e fora da Lia; senão nil. Quem monta o catálogo passa por aqui: a página
  # com endereço presencial ainda sem coordenada (a que existia antes da flag) pede o job (`GeocodificarLocaisJob.pedir`,
  # uma vez por página e pendentes), e o mapa entra no catálogo de um turno seguinte. Sem pendente, nem o Redis é lido.
  def pagina(agent)
    return if agent.agent_type == LIA || !ligado?(agent.account)

    ::Autonomia::Agents::Tools::Native::Agenda.pagina_de(agent).tap { |pagina| pedir_coordenada(pagina) }
  end

  # Erro ao pedir não derruba o catálogo: o log leva só o id da página e a classe.
  def pedir_coordenada(pagina)
    return if pagina.nil? || pagina.enderecos_sem_coordenada.empty?

    ::Crm::BookingV2::GeocodificarLocaisJob.pedir(pagina)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][cartao_da_pagina] geocodificar_nao_pedido page_id=#{pagina.id} #{e.class.name}")
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

  # O cartão de contato da página: o nome (o título da página ou o nome da conta, até 100; nunca o nome público, que pode
  # ser o de uma pessoa da equipe) e o `contact_phone` com "+" e só os dígitos. nil quando o telefone ou o nome não servem
  # para o tipo.
  def contato(pagina)
    return if pagina.nil?

    telefone = telefone(pagina.contact_phone)
    nome = (pagina.title.presence || pagina.account.name).to_s.squish.first(::RichMessages::Types::Contact::NAME_MAX)
    formato = { 'type' => 'contact', 'name' => nome, 'phone' => telefone }
    formato if telefone && ::RichMessages::Types::Contact.new(formato).error_for('').nil?
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
