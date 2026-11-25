# OS PLANOS DE UMA COTAÇÃO do Seguro Viagem (#3211): transforma a resposta do `POST /v1/Cotacao` da Universal na
# lista que a cotação guarda, o PDF imprime e a proposta lê.
#
# LISTA BRANCA (R2): cada plano é montado campo a campo; o produto cru nunca é copiado. Comissão, markup, ranking,
# `quotationPorcentagem*` e `valorSemDesconto*` ficam na resposta e não chegam ao modelo, ao PDF nem ao banco.
#
# FILTRO: só entra plano com despesas médicas e hospitalares (`IDS_DMH`) e que aceita a idade de todos os viajantes.
# O filtro de despesas médicas só vale quando o catálogo da resposta conhece algum id de `IDS_DMH`: num destino com
# ids que ainda não conhecemos ele não zera a lista; deixa um aviso no log com os ids do catálogo para acharmos o novo.
#
# Os valores de cobertura (`principais`, `coberturas`) são o texto que a Universal escreve ("R$ 100.000"), sem prefixo
# nosso. O preço vai em texto decimal (`'360.0'`): quem formata em reais é `Dinheiro.brl`.
module Autonomia::Agents::Tools::Native::SeguroViagem::Planos
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  IDS_DMH = [2898].freeze
  IDS_BAGAGEM = [2595].freeze
  IDS_CANCELAMENTO = [2601].freeze

  module_function

  # -> Array<Hash> com chaves em texto, `codigo` "P1", "P2"... na ordem da Universal depois do filtro.
  def de(resposta, idades:)
    catalogo = catalogo_de(resposta)
    produtos = com_despesas_medicas(Array(resposta['produtos']).grep(Hash), catalogo)
    planos = produtos.map { |produto| plano(produto, catalogo, resposta['valorDoCambio']) }
    planos.select { |plano| aceita?(plano, idades) }
          .each_with_index.map { |plano, indice| { 'codigo' => "P#{indice + 1}" }.merge(plano) }
  end

  # O que o modelo lê: o código, o nome, o preço em reais, as parcelas e as três coberturas principais.
  def resumo(planos)
    planos.map do |plano|
      { 'codigo' => plano['codigo'], 'nome' => plano['nome'],
        'preco_total' => plano['preco_total'].nil? ? nil : SeguroViagem::Dinheiro.brl(plano['preco_total']),
        'max_parcelas' => plano['max_parcelas'], 'principais' => plano['principais'] }
    end
  end

  # { id_beneficio => benefício do catálogo da resposta }
  def catalogo_de(resposta)
    Array(resposta['beneficios']).grep(Hash).each_with_object({}) do |beneficio, catalogo|
      id = id_de(beneficio)
      catalogo[id] ||= beneficio unless id.nil?
    end
  end

  def com_despesas_medicas(produtos, catalogo)
    unless catalogo.keys.intersect?(IDS_DMH)
      Rails.logger.warn("[seguro_viagem] catálogo sem id conhecido de despesas médicas ids=#{catalogo.keys.join(',')}")
      return produtos
    end

    produtos.select { |produto| beneficios(produto).any? { |beneficio| IDS_DMH.include?(id_de(beneficio)) } }
  end

  def plano(produto, catalogo, cambio_da_resposta)
    tarifa = produto['tarifa'].is_a?(Hash) ? produto['tarifa'] : {}
    {
      'id_produto' => produto['idProduto'], 'id_produto_acordo' => produto['idProdutoAcordo'],
      'nome' => produto['descricao'].to_s.strip, 'descricao_adicional' => produto['descricaoAdicional'],
      'preco_total' => decimal(tarifa['valor']), 'valor_moeda' => decimal(tarifa['valorMoeda']),
      'moeda' => produto['simboloMoeda'], 'cambio' => cambio_da_resposta.nil? ? tarifa['cambio'] : cambio_da_resposta,
      'max_parcelas' => produto['maxParcelas'], 'idade_minima' => produto['idadeMinima'],
      'idade_maxima' => produto['idadeMaxima'], 'regra_cancelamento' => produto['regraCancelamento'],
      'faixas' => faixas(tarifa), 'coberturas' => coberturas(produto, catalogo), 'principais' => principais(produto)
    }
  end

  def faixas(tarifa)
    Array(tarifa['tarifaIdade']).grep(Hash).map do |faixa|
      { 'de' => faixa['de'], 'ate' => faixa['ate'], 'valor' => decimal(faixa['valor']),
        'valor_moeda' => decimal(faixa['valorMoeda']) }
    end
  end

  def coberturas(produto, catalogo)
    beneficios(produto).map do |beneficio|
      item = catalogo[id_de(beneficio)].to_h
      { 'id_beneficio' => id_de(beneficio), 'nome' => item['descricao'], 'descricao_completa' => item['descricaoCompleta'],
        'valor' => beneficio['valor'], 'moeda' => beneficio['tipoMoeda'] }
    end
  end

  def principais(produto)
    { 'despesas_medicas' => principal(produto, IDS_DMH), 'bagagem' => principal(produto, IDS_BAGAGEM),
      'cancelamento' => principal(produto, IDS_CANCELAMENTO) }
  end

  # O texto `valor` como a Universal entrega; em branco, a moeda e o valor em dinheiro; sem o benefício, nil.
  def principal(produto, ids)
    beneficio = beneficios(produto).find { |item| ids.include?(id_de(item)) }
    return nil if beneficio.nil?

    beneficio['valor'].to_s.strip.presence || "#{beneficio['tipoMoeda']} #{beneficio['valorEmDinheiro']}".strip.presence
  end

  # A idade de todos os viajantes dentro de `idade_minima..idade_maxima` (a mesma regra de `Faixas`).
  def aceita?(plano, idades)
    minima = plano['idade_minima']
    maxima = plano['idade_maxima']
    idades.all? { |idade| (minima.nil? || idade >= minima.to_i) && (maxima.nil? || idade <= maxima.to_i) }
  end

  def beneficios(produto)
    Array(produto['beneficios']).grep(Hash)
  end

  def id_de(beneficio)
    Integer(beneficio['idBeneficio'], exception: false)
  end

  # `360` -> `'360.0'`; nil fica nil.
  def decimal(valor)
    valor.nil? ? nil : BigDecimal(valor.to_s).to_s('F')
  end

  private_class_method :catalogo_de, :com_despesas_medicas, :plano, :faixas, :coberturas, :principais, :principal,
                       :aceita?, :beneficios, :id_de, :decimal
end
