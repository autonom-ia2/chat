# O DIRETÓRIO DO OPEN INSURANCE BRASIL resumido: de cada marca ativa (o `AuthorisationServer` de cada participante), o
# nome, a empresa e o endereço de cada ramo de produtos atendido aqui. Do que o diretório lista, só entra:
#   - a família ativa de "products-services" que é um dos `RAMOS` (o modelo escolhe pela lista);
#   - o endereço HTTPS na porta 443, sem usuário e sem marcador a preencher (`{fipeCode}`: o auto e o residencial);
#   - de várias versões da mesma família, a maior.
# O índice vale `VALIDADE` no cache (o diretório tem 2 MB e muda pouco). Diretório fora do formato (não é lista, ou nenhuma
# marca sobrou): falha, e nada é guardado.
module Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Diretorio
  Falha = Autonomia::FerramentasProntas::Provedor::Falha

  CHAVE = 'autonomia:prontas:v1:produtos_seguradoras:diretorio'.freeze
  VALIDADE = 6.hours
  CAMINHO = '/participants'.freeze
  MAX_BYTES = 6.megabytes
  ATIVO = 'Active'.freeze
  FAMILIA = 'products-services_'.freeze
  MARCADOR = '{'.freeze

  module_function

  # -> o índice guardado, ou o que o bloco baixar (o JSON do diretório), resumido e guardado.
  def indice
    guardado = ler
    return guardado if guardado.present?

    resumido = resumir(yield)
    gravar(resumido)
    resumido
  end

  def resumir(participantes)
    raise Falha, 'resposta_invalida' unless participantes.is_a?(Array)

    marcas = participantes.select { |item| item.is_a?(Hash) && item['Status'] == ATIVO }.flat_map { |item| marcas(item) }
    raise Falha, 'resposta_invalida' if marcas.empty?

    marcas.sort_by { |marca| Autonomia::FerramentasProntas::Lista.comparavel(marca['nome']) }
  end

  def marcas(participante)
    Array(participante['AuthorisationServers']).filter_map do |servidor|
      next unless servidor.is_a?(Hash) && servidor['Status'] == ATIVO

      enderecos = enderecos(servidor['ApiResources'])
      nome = servidor['CustomerFriendlyName'].to_s.squish.presence
      { 'nome' => nome, 'empresa' => participante['OrganisationName'].to_s.squish, 'ramos' => enderecos } if nome && enderecos.any?
    end
  end

  # -> { ramo => endereço }, a maior versão de cada família.
  def enderecos(recursos)
    escolhidos = Array(recursos).each_with_object({}) do |recurso, por_ramo|
      ramo, endereco, versao = recurso_valido(recurso)
      next if ramo.nil? || (por_ramo[ramo] && por_ramo[ramo].last >= versao)

      por_ramo[ramo] = [endereco, versao]
    end
    escolhidos.sort.to_h.transform_values(&:first)
  end

  # -> [ramo, endereço, versão], ou nil quando o recurso não serve.
  def recurso_valido(recurso)
    return unless produtos_ativos?(recurso)

    ramo = Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras.ramo_da_familia(recurso['ApiFamilyType'])
    versao = recurso['ApiVersion'].to_s
    endereco = endereco(recurso['ApiDiscoveryEndpoints'])
    [ramo, endereco, Gem::Version.new(versao)] if ramo && endereco && Gem::Version.correct?(versao)
  end

  def produtos_ativos?(recurso)
    recurso.is_a?(Hash) && recurso['Status'] == ATIVO && recurso['ApiFamilyType'].to_s.start_with?(FAMILIA)
  end

  def endereco(pontos)
    Array(pontos).filter_map { |item| item['ApiEndpoint'] if item.is_a?(Hash) }.find { |url| aceito?(url) }
  end

  def aceito?(url)
    return false if url.to_s.include?(MARCADOR)

    destino = URI.parse(url.to_s)
    destino.is_a?(URI::HTTPS) && destino.host.present? && destino.port == 443 && destino.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  # O cache fora do ar é só um cache a menos: o diretório é baixado de novo.
  def ler
    Rails.cache.read(CHAVE)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][pronta] diretório do Open Insurance: cache de leitura falhou #{e.class}")
    nil
  end

  def gravar(indice)
    Rails.cache.write(CHAVE, indice, expires_in: VALIDADE)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][pronta] diretório do Open Insurance: cache de escrita falhou #{e.class}")
  end
end
