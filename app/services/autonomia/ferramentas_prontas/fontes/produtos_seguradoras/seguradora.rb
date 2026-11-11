# UMA SEGURADORA no endereço que o diretório do Open Insurance deu (`Diretorio`), resumida ao que o agente precisa: o nome
# de cada produto, as coberturas e o link das condições. A resposta da seguradora é enorme (limites, carências, formas de
# pagamento): nada disso vai ao modelo. O produto e a cobertura de sandbox e o link de exemplo saem aqui (`Sujeira`).
#
# O host é dinâmico (cada seguradora tem o seu, e muda sem aviso): o `ClienteHttp` da consulta passa a aceitá-lo
# (`permitir_host!`), com as mesmas proteções (HTTPS na 443, IP privado barrado, redirecionamento só para a mesma origem,
# teto de tamanho, teto global por host, fatia da conta e o host desligado pela configuração) e o prazo final da consulta.
# Só a primeira página (o `page-size` quebra parte das seguradoras); `total_na_fonte` avisa quando há mais.
class Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Seguradora
  Falha = Autonomia::FerramentasProntas::Provedor::Falha
  NaoEncontrado = Autonomia::FerramentasProntas::Provedor::NaoEncontrado

  # A página de produtos de pessoas da BrasilSeg tem 800 KB.
  MAX_BYTES = 2.megabytes
  # Itaú, Mapfre e BrasilSeg recusam o pedido sem ele (400, "cache-control é obrigatório").
  CABECALHOS = { 'Cache-Control' => 'no-cache' }.freeze
  MAX_COBERTURAS = Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::MAX_COBERTURAS
  Sujeira = Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Sujeira

  def initialize(marca, endereco, prazo:, cliente:)
    @marca = marca
    @destino = URI.parse(endereco)
    @prazo = prazo
    @cliente = cliente
  end

  # -> { 'seguradora', 'produtos' => [{ 'nome', 'coberturas', 'condicoes' }], 'total_na_fonte'? }, ou `Falha`.
  def produtos
    @cliente.permitir_host!(@destino.host)
    corpo = @cliente.get_json(@destino.host, @destino.request_uri, prazo: @prazo, max_bytes: MAX_BYTES, cabecalhos: CABECALHOS)
    lidos = lidos(corpo)
    itens = lidos.filter_map { |produto| produto(produto) }.uniq { |item| item['nome'] }
    { 'seguradora' => @marca['nome'], 'produtos' => itens, 'total_na_fonte' => mais_na_fonte(corpo, lidos.size) }.compact
  rescue NaoEncontrado
    raise Falha, 'endereco_sumiu'
  end

  private

  # O total que a seguradora diz ter, só quando passa do que veio nesta página (o mesmo produto em duas empresas do grupo
  # conta duas vezes lá e uma aqui).
  def mais_na_fonte(corpo, lidos)
    total = corpo['meta'].is_a?(Hash) ? corpo['meta']['totalRecords'] : nil
    total if total.is_a?(Integer) && total > lidos
  end

  # O formato do Open Insurance: data.brand.companies[].products[]. Fora dele: falha (a seguradora mudou o formato).
  def lidos(corpo)
    empresas = empresas(corpo)
    raise Falha, 'resposta_invalida' unless empresas.is_a?(Array)

    empresas.select { |empresa| empresa.is_a?(Hash) }.flat_map { |empresa| Array(empresa['products']) }.select { |item| item.is_a?(Hash) }
  end

  def empresas(corpo)
    dados = corpo['data'] if corpo.is_a?(Hash)
    marca = dados['brand'] if dados.is_a?(Hash)
    marca['companies'] if marca.is_a?(Hash)
  end

  def produto(produto)
    nome = produto['name'].to_s.squish.presence
    return if nome.nil? || Sujeira.produto_de_exemplo?(nome)

    coberturas = Array(produto['coverages']).filter_map { |item| cobertura(item) }.uniq.first(MAX_COBERTURAS)
    { 'nome' => nome, 'coberturas' => coberturas, 'condicoes' => condicoes(produto['termsAndConditions']) }.compact
  end

  # A descrição da seguradora, ou o código da cobertura legível ("INVALIDEZ_PERMANENTE" -> "Invalidez permanente"). A de
  # sandbox ("string") sai.
  def cobertura(item)
    return unless item.is_a?(Hash)

    texto = item['coverageDescription'].to_s.squish.presence || item['coverage'].to_s.tr('_', ' ').squish.capitalize.presence
    texto unless Sujeira.cobertura_de_exemplo?(texto)
  end

  # O link das condições gerais: o primeiro que abre, não é de exemplo e cabe inteiro na resposta (cortado, não abre).
  def condicoes(termos)
    Array.wrap(termos).filter_map { |item| item['definition'].to_s.strip if item.is_a?(Hash) }.find do |link|
      Sujeira.link_das_condicoes?(link) && link.length <= Autonomia::FerramentasProntas::Resposta::MAX_TEXTO
    end
  end
end
