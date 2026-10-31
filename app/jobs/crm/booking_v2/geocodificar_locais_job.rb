# CONVERTE O ENDEREÇO PRESENCIAL DA PÁGINA EM COORDENADA (#1479 F3), para o mapa que o agente manda
# (`enviar_localizacao`). Enfileirado depois do commit, quando o endereço entra ou muda (`Crm::BookingPageCoordenadas`),
# e pela tarefa `autonomia:agentes:geocodificar_paginas`. Nunca no turno do agente.
#
# Por endereço sem coordenada: a primeira sugestão do Google Places da plataforma e o detalhe dela, na mesma sessão
# (`ConversaCanal::BuscaDeLugar`, que cobra a busca como uma só). Grava SÓ `latitude` e `longitude`, relendo a página
# com a linha travada, no item `in_person` cujo endereço ainda é o mesmo, direto na coluna (`update_column`: sem
# callbacks, sem `updated_at`, sem mexer no resto). O endereço que mudou enquanto o job rodava não ganha a coordenada do
# antigo; o salvar dele já enfileirou outro job.
#
# Google fora (`ProviderError`): nada gravado e UMA nova tentativa; na segunda falha, desiste com registro. Sem
# resultado, ou sem coordenada no detalhe: nada gravado. Sem a chave da plataforma ou com a conta desligada: nada.
# O registro leva o id da página e o status, nunca o endereço nem a coordenada.
class Crm::BookingV2::GeocodificarLocaisJob < ApplicationJob
  ATTEMPTS = 2
  RETRY_WAIT = 1.minute
  PRESENCIAL = Crm::BookingPageCoordenadas::PRESENCIAL
  COORDENADA = [Integer, Float].freeze

  queue_as :low

  retry_on Autonomia::Prospecting::SearchRunner::ProviderError, wait: RETRY_WAIT, attempts: ATTEMPTS do |job, _error|
    job.registrar(job.arguments.first, 'google_falhou')
  end

  def perform(page_id)
    pagina = ::Crm::AgentBookingProfile.new_pages.find_by(id: page_id)
    return if pagina.nil?
    return registrar(page_id, 'conta_desligada') unless ::Autonomia::Agents::Tools::Native::CartaoDaPagina.ligado?(pagina.account)
    return registrar(page_id, 'sem_chave') unless ::ConversaCanal::BuscaDeLugar.configurada?

    pagina.enderecos_sem_coordenada.each { |endereco| geocodificar(pagina, endereco) }
  end

  def registrar(page_id, status)
    Rails.logger.info("[crm][booking_v2][geocodificar] page_id=#{page_id} status=#{status}")
  end

  private

  def geocodificar(pagina, endereco)
    busca = ::ConversaCanal::BuscaDeLugar.para(pagina.account, sessao: SecureRandom.hex(16))
    sugestao = busca.suggestions(endereco).first
    return registrar(pagina.id, 'sem_resultado') if sugestao.nil?

    lugar = busca.details(sugestao[:place_id])
    return registrar(pagina.id, 'sem_coordenada') unless coordenada?(lugar[:latitude]) && coordenada?(lugar[:longitude])

    registrar(pagina.id, gravar(pagina.id, endereco, lugar[:latitude], lugar[:longitude]))
  end

  def coordenada?(valor)
    COORDENADA.any? { |classe| valor.is_a?(classe) } && valor.finite?
  end

  # -> o status. Relê a página com a linha travada: só o item cujo endereço ainda é este, e só as duas chaves.
  def gravar(page_id, endereco, latitude, longitude)
    ::Crm::AgentBookingProfile.transaction do
      pagina = ::Crm::AgentBookingProfile.lock.find_by(id: page_id)
      next 'pagina_apagada' if pagina.nil?

      lista = Array(pagina.locations)
      next 'endereco_mudou' if lista.none? { |item| deste_endereco?(item, endereco) }

      ponto = { 'latitude' => latitude, 'longitude' => longitude }
      pagina.update_column(:locations, lista.map { |item| deste_endereco?(item, endereco) ? item.merge(ponto) : item }) # rubocop:disable Rails/SkipsModelValidations
      'gravado'
    end
  end

  def deste_endereco?(item, endereco)
    item.is_a?(Hash) && item['type'] == PRESENCIAL && item['address'] == endereco
  end
end
