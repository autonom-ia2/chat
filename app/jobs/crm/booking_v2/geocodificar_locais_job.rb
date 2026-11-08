# CONVERTE O ENDEREÇO PRESENCIAL DA PÁGINA EM COORDENADA (#1479 F3), para o mapa que o agente manda
# (`enviar_localizacao`). Nunca no turno do agente nem no salvar: só pelo disparo único `pedir`, que o salvar da página
# (`Crm::BookingPageCoordenadas`, depois do commit) e o catálogo do agente (`CartaoDaPagina.pagina`) chamam. Assim a
# página que já existia antes da flag ganha a coordenada no turno seguinte, sem tarefa à parte.
#
# PENDENTE é o endereço presencial sem coordenada, sem a marca "não achou" para o endereço atual
# (`enderecos_sem_coordenada`) e com menos de TETO_DE_FALHAS falhas passageiras. `pedir` só enfileira com a conta ligada
# e algum pendente, e uma vez por TRAVA para a mesma página e os mesmos pendentes (SET NX); endereço novo, chave nova.
#
# Por endereço pendente: SÓ a primeira sugestão do Google Places da plataforma e o detalhe dela, na mesma sessão
# (`Busca`). Risco conhecido: se a primeira não for o lugar certo e as outras fossem, o endereço fica "não achou" até
# mudar (não comparamos as sugestões entre si, que seria decidir pelo texto).
# Só vale o lugar PRECISO, pelo tipo que o Google devolve (`preciso?`), nunca pelo texto. Grava relendo a página com a
# linha travada, no item `in_person` cujo endereço ainda é o mesmo, só as chaves dele, direto na coluna (`update_column`:
# sem callbacks, sem `updated_at`, sem mexer no resto). O endereço que mudou enquanto o job rodava não ganha nada do antigo.
#   - achou e é preciso: `latitude` e `longitude`;
#   - falha definitiva (sem sugestão, detalhe sem coordenada, lugar impreciso): a marca NAO_ACHOU com o hash do endereço.
#     Ele deixa de ser pendente até o endereço mudar (o `before_save` da página só mantém a marca do mesmo endereço);
#   - Google fora (`ProviderError`): nada gravado; a falha conta no Redis (página + hash do endereço, 7 dias). No teto,
#     desiste com erro no log e no tracker. Abaixo dele, o próximo `pedir`, depois da trava, tenta de novo.
# Sem a chave da plataforma ou com a conta desligada: nada. O registro leva o id da página e o status, nunca o endereço
# nem a coordenada.
class Crm::BookingV2::GeocodificarLocaisJob < ApplicationJob
  PRESENCIAL = Crm::BookingPageCoordenadas::PRESENCIAL
  NAO_ACHOU = Crm::BookingPageCoordenadas::NAO_ACHOU
  COORDENADA = [Integer, Float].freeze
  TRAVA = 1.hour
  TETO_DE_FALHAS = 3
  VALIDADE_DAS_FALHAS = 7.days
  CHAVE = 'crm:booking_v2:geocodificar'.freeze
  # O PRECISO É O QUE LEVA A PESSOA À PORTA. Decisão da coordenadora (#1479 F3): pelo tipo do lugar no Places API (New),
  # nunca pelo texto. Vale o endereço com número (`street_address`), o prédio (`premise`, `subpremise`) e o
  # estabelecimento: todo tipo de estabelecimento da Tabela A (dentista, clínica, loja) vem com `establishment` e
  # `point_of_interest` em `types`.
  TIPOS_PRECISOS = %w[street_address premise subpremise establishment point_of_interest].freeze
  # O mapa da rua inteira, do bairro, da cidade ou do CEP leva ao lugar errado. Recusado quando é o tipo principal, mesmo
  # se `types` trouxer `point_of_interest` (a cidade marcada como ponto turístico).
  TIPOS_IMPRECISOS = %w[
    route intersection neighborhood colloquial_area political country locality postal_town
    sublocality sublocality_level_1 sublocality_level_2 sublocality_level_3 sublocality_level_4 sublocality_level_5
    postal_code postal_code_prefix postal_code_suffix
    administrative_area_level_1 administrative_area_level_2 administrative_area_level_3 administrative_area_level_4
    administrative_area_level_5 administrative_area_level_6 administrative_area_level_7
  ].freeze

  # A falha que o tracker recebe no teto: só o id da página e o número de falhas (a mensagem do Google fica de fora).
  class GoogleIndisponivel < StandardError; end

  queue_as :low

  class << self
    # O disparo único. -> true quando enfileirou.
    def pedir(pagina)
      return false unless pagina&.new_page? && ::Autonomia::Agents::Tools::Native::CartaoDaPagina.ligado?(pagina.account)

      enderecos = pendentes(pagina)
      return false if enderecos.empty?

      trava = chave_da_trava(pagina.id, enderecos)
      return false unless Redis::Alfred.set(trava, 1, nx: true, ex: TRAVA.to_i)

      enfileirar(pagina.id, trava)
    end

    # Erro ao enfileirar: a trava sai (senão a página ficaria uma hora sem pedido) e o erro sobe a quem chamou.
    def enfileirar(page_id, trava)
      perform_later(page_id)
      true
    rescue StandardError
      Redis::Alfred.delete(trava)
      raise
    end

    def pendentes(pagina)
      pagina.enderecos_sem_coordenada.reject { |endereco| falhas(pagina.id, endereco) >= TETO_DE_FALHAS }
    end

    def falhas(page_id, endereco)
      Redis::Alfred.get(chave_das_falhas(page_id, endereco)).to_i
    end

    # -> o total de falhas depois desta.
    def contar_falha(page_id, endereco)
      chave = chave_das_falhas(page_id, endereco)
      # Juntos (MULTI): o contador nunca fica sem validade.
      Redis::Alfred.with do |conn|
        conn.multi do |transacao|
          transacao.incr(chave)
          transacao.expire(chave, VALIDADE_DAS_FALHAS.to_i)
        end
      end.first
    end

    private

    def chave_da_trava(page_id, enderecos)
      "#{CHAVE}:trava:#{page_id}:#{Digest::SHA256.hexdigest(enderecos.sort.join("\n")).first(16)}"
    end

    def chave_das_falhas(page_id, endereco)
      "#{CHAVE}:falhas:#{page_id}:#{Crm::BookingPageCoordenadas.hash_do_endereco(endereco)}"
    end
  end

  def perform(page_id)
    pagina = ::Crm::AgentBookingProfile.new_pages.find_by(id: page_id)
    return if pagina.nil?
    return registrar(page_id, 'conta_desligada') unless ::Autonomia::Agents::Tools::Native::CartaoDaPagina.ligado?(pagina.account)
    return registrar(page_id, 'sem_chave') unless Busca.configurada?

    self.class.pendentes(pagina).each { |endereco| geocodificar(pagina, endereco) }
  end

  private

  def registrar(page_id, status)
    Rails.logger.info("[crm][booking_v2][geocodificar] page_id=#{page_id} status=#{status}")
  end

  def geocodificar(pagina, endereco)
    lugar = lugar_no_google(pagina.account, endereco)
    return nao_achou(pagina.id, endereco, 'sem_resultado') if lugar.nil?
    return nao_achou(pagina.id, endereco, 'sem_coordenada') unless coordenada?(lugar[:latitude]) && coordenada?(lugar[:longitude])
    return nao_achou(pagina.id, endereco, 'impreciso') unless preciso?(lugar)

    registrar(pagina.id, gravar(pagina.id, endereco, 'latitude' => lugar[:latitude], 'longitude' => lugar[:longitude]))
  rescue Autonomia::Prospecting::SearchRunner::ProviderError
    falhou(pagina, endereco)
  end

  # A primeira sugestão e o detalhe dela, na mesma sessão. nil sem sugestão (ou com um id que não é do Google).
  def lugar_no_google(account, endereco)
    busca = Busca.para(account, sessao: SecureRandom.hex(16))
    sugestao = busca.suggestions(endereco).first
    busca.details(sugestao[:place_id]) if sugestao && Busca.id_do_google?(sugestao[:place_id])
  end

  def preciso?(lugar)
    tipos = Array(lugar[:tipos]) + [lugar[:tipo_principal]].compact
    tipos.intersect?(TIPOS_PRECISOS) && TIPOS_IMPRECISOS.exclude?(lugar[:tipo_principal])
  end

  def nao_achou(page_id, endereco, motivo)
    status = gravar(page_id, endereco, NAO_ACHOU => Crm::BookingPageCoordenadas.hash_do_endereco(endereco))
    registrar(page_id, "#{motivo}_#{status}")
  end

  def falhou(pagina, endereco)
    falhas = self.class.contar_falha(pagina.id, endereco)
    return registrar(pagina.id, "google_falhou falhas=#{falhas}") if falhas < TETO_DE_FALHAS

    Rails.logger.error("[crm][booking_v2][geocodificar] page_id=#{pagina.id} status=desistiu falhas=#{falhas}")
    ChatwootExceptionTracker.new(GoogleIndisponivel.new("page_id=#{pagina.id} falhas=#{falhas}"), account: pagina.account)
                            .capture_exception
  end

  def coordenada?(valor)
    COORDENADA.any? { |classe| valor.is_a?(classe) } && valor.finite?
  end

  # -> o status. Relê a página com a linha travada: só o item cujo endereço ainda é este, e só as chaves dadas.
  def gravar(page_id, endereco, dados)
    ::Crm::AgentBookingProfile.transaction do
      pagina = ::Crm::AgentBookingProfile.lock.find_by(id: page_id)
      next 'pagina_apagada' if pagina.nil?

      lista = Array(pagina.locations)
      next 'endereco_mudou' if lista.none? { |item| deste_endereco?(item, endereco) }

      pagina.update_column(:locations, lista.map { |item| deste_endereco?(item, endereco) ? item.merge(dados) : item }) # rubocop:disable Rails/SkipsModelValidations
      'gravado'
    end
  end

  def deste_endereco?(item, endereco)
    item.is_a?(Hash) && item['type'] == PRESENCIAL && item['address'] == endereco
  end
end
